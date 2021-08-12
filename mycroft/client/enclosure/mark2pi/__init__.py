# Copyright 2017 Mycroft AI Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
import os
import subprocess
import time
import sys
from alsaaudio import Mixer
from threading import Thread, Timer

import mycroft.dialog
from mycroft.client.enclosure.base import Enclosure
from mycroft.api import has_been_paired
from mycroft.audio import wait_while_speaking
from mycroft.enclosure.display_manager import \
    init_display_manager_bus_connection
from mycroft.messagebus.message import Message
from mycroft.util import connected
from mycroft.util.log import LOG


class EnclosureMark2Pi(Enclosure):
    """
    Serves as a communication interface between a simple text frontend and
    Mycroft Core.  This is used for Picroft or other headless systems,
    and/or for users of the CLI.
    """

    _last_internet_notification = 0

    def __init__(self):
        super().__init__()

        # Notifications from mycroft-core
        self.bus.on("enclosure.notify.no_internet", self.on_no_internet)

        # Handle Wi-Fi Setup visuals
        self.resources_dir = '/opt/mycroft/skills/skill-mark-2-pi.mycroftai/ui'
        self.bus.on('system.wifi.ap_up',
                        self.handle_ap_up)
        self.bus.on('system.wifi.ap_device_connected',
                       self.handle_wifi_device_connected)
        self.bus.on('system.wifi.ap_device_disconnected',
                        self.handle_ap_up)
        self.bus.on('system.wifi.ap_connection_success',
                        self.handle_ap_success)

        # initiates the web sockets on display manager
        # NOTE: this is a temporary place to connect the display manager
        init_display_manager_bus_connection()

        # verify internet connection and prompt user on bootup if needed
        if not connected():
            # We delay this for several seconds to ensure that the other
            # clients are up and connected to the messagebus in order to
            # receive the "speak".  This was sometimes happening too
            # quickly and the user wasn't notified what to do.
            Timer(5, self._do_net_check).start()

    def handle_ap_up(self, message):
        # 1-wifi-follow-prompt.fb
        # 4-pairing-home.fb
        # 5-pairing-success.fb
        # 6-intro.fb
        draw_file(os.join(self.resources_dir, '0-wifi-connect.fb'))
        LOG.info('WAGNER enclosure ap up')

    def handle_wifi_device_connected(self, message):
        draw_file(os.join(self.resources_dir, '2-wifi-choose-network.fb'))
        LOG.info('WAGNER enclosure ap connected')

    def handle_ap_success(self, message):
        draw_file(os.join(self.resources_dir, '3-wifi-success.fb'))
        LOG.info('WAGNER enclosure ap success')

    def on_no_internet(self, event=None):
        if connected():
            # One last check to see if connection was established
            return

        if time.time() - Enclosure._last_internet_notification < 30:
            # don't bother the user with multiple notifications with 30 secs
            return

        Enclosure._last_internet_notification = time.time()

        # TODO: This should go into EnclosureMark1 subclass of Enclosure.
        if has_been_paired():
            # Handle the translation within that code.
            self.bus.emit(Message("speak", {
                'utterance': "This device is not connected to the Internet. "
                             "Either plug in a network cable or set up your "
                             "wifi connection."}))
        else:
            # enter wifi-setup mode automatically
            self.bus.emit(Message('system.wifi.setup', {'lang': self.lang}))

    def speak(self, text):
        self.bus.emit(Message("speak", {'utterance': text}))

    def _handle_pairing_complete(self, Message):
        """
        Handler for 'mycroft.paired', unmutes the mic after the pairing is
        complete.
        """
        self.bus.emit(Message("mycroft.mic.unmute"))

    def _do_net_check(self):
        # TODO: This should live in the derived Enclosure, e.g. EnclosureMark1
        LOG.info("Checking internet connection")
        if not connected():  # and self.conn_monitor is None:
            if has_been_paired():
                # TODO: Enclosure/localization
                self.speak("This unit is not connected to the Internet. "
                           "Either plug in a network cable or setup your "
                           "wifi connection.")
            else:
                # Begin the unit startup process, this is the first time it
                # is being run with factory defaults.

                # TODO: This logic should be in EnclosureMark1
                # TODO: Enclosure/localization

                # Don't listen to mic during this out-of-box experience
                self.bus.emit(Message("mycroft.mic.mute"))
                # Setup handler to unmute mic at the end of on boarding
                # i.e. after pairing is complete
                self.bus.once('mycroft.paired', self._handle_pairing_complete)

                self.speak(mycroft.dialog.get('mycroft.intro'))
                wait_while_speaking()
                time.sleep(2)  # a pause sounds better than just jumping in

                # Kick off wifi-setup automatically
                data = {'allow_timeout': False, 'lang': self.lang}
                self.bus.emit(Message('system.wifi.setup', data))

    def draw_file(self, file_path, dev='/dev/fb0'):
        """ Writes a file directly to the framebuff device.
        Arguments:
            file_path (str): path to file to be drawn to frame buffer device
            dev (str): Optional framebuffer device to write to
        """
        with open(file_path, 'rb') as img:
            with open(dev, 'wb') as fb:
                fb.write(img.read())
