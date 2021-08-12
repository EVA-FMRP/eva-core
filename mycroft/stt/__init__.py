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
from mycroft.api import STTApi, HTTPError
from mycroft.configuration import Configuration
from mycroft.util.log import LOG
from mycroft.util.json_helper import merge_dict
from speech2text.engines import STT
from speech2text import STTFactory as BaseSTTFactory


def requires_pairing(func):
    """Decorator kicking of pairing sequence if client is not allowed access.

    Checks the http status of the response if an HTTP error is recieved. If
    a 401 status is detected returns "pair my device" to trigger the pairing
    skill.
    """
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except HTTPError as e:
            if e.response.status_code == 401:
                LOG.warning('Access Denied at mycroft.ai')
                # phrase to start the pairing process
                return 'pair my device'
            else:
                raise
    return wrapper


class MycroftSTT(STT):
    """Default mycroft STT."""
    def __init__(self, config=None):
        config = config or Configuration.get().get("stt", {})
        super(MycroftSTT, self).__init__(config)
        self.api = STTApi("stt")

    @requires_pairing
    def execute(self, audio, language=None):
        self.lang = language or self.lang
        try:
            return self.api.stt(audio.get_flac_data(convert_rate=16000),
                                self.lang, 1)[0]
        except Exception:
            return self.api.stt(audio.get_flac_data(), self.lang, 1)[0]


class MycroftDeepSpeechSTT(STT):
    """Mycroft Hosted DeepSpeech"""
    def __init__(self, config=None):
        config = config or Configuration.get().get("stt", {})
        super(MycroftDeepSpeechSTT, self).__init__(config)
        self.api = STTApi("deepspeech")

    @requires_pairing
    def execute(self, audio, language=None):
        language = language or self.lang
        if not language.startswith("en"):
            raise ValueError("Deepspeech is currently english only")
        return self.api.stt(audio.get_wav_data(), self.lang, 1)


class STTFactory:
    CLASSES = {
        "mycroft": MycroftSTT,
        "mycroft_deepspeech": MycroftDeepSpeechSTT
    }

    @staticmethod
    def create():
        config = Configuration.get().get("stt", {})
        # add mycroft-core engines to factory
        engines = BaseSTTFactory.CLASSES.copy()
        merge_dict(engines, STTFactory.CLASSES)
        try:
            return BaseSTTFactory.create(config, engines)
        except Exception as e:
            # The selected STT engine failed to start.
            # Report it and fall back to default.
            LOG.exception('The selected STT backend could not be loaded, '
                          'falling back to default...')
            if config.get("module", "") != 'mycroft':
                return MycroftSTT(config)
            else:
                raise
