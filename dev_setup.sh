#!/usr/bin/env bash
#
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
##########################################################################

# Set a default locale to handle output from commands reliably
export LANG=C.UTF-8
export LANGUAGE=pt

# exit on any error
set -Ee

cd $(dirname $0)
TOP=$(pwd -L)

function clean_mycroft_files() {
    echo '
Isso removerá completamente todos os arquivos instalados pelo mycroft (incluindo o emparelhamento
em formação).
Você deseja continuar? (s/n)'
    while true; do
        read -N1 -s key
        case $key in
        [Ss])
            sudo rm -rf /var/log/mycroft
            rm -f /var/tmp/mycroft_web_cache.json
            rm -rf "${TMPDIR:-/tmp}/mycroft"
            rm -rf "$HOME/.mycroft"
            sudo rm -rf "/opt/mycroft"
            exit 0
            ;;
        [Nn])
            exit 1
            ;;
        esac
    done
    

}
function show_help() {
    echo '
Uso: dev_setup.sh [opções]
Prepare seu ambiente para executar os serviços mycroft-core.

Opções:
     --clean 				Remove arquivos e pastas criados por este script
     -h, --help 			Mostrar esta mensagem
     -fm 					Forçar compilação de mímica
     -n, --no-error 		Não sai em caso de erro (use com cuidado)
     -p arg, --python arg 	Define a versão python a ser usada
     -r, --allow-root 		Permitir a execução como root (por exemplo, sudo)
     -sm 					Pular compilação de mímica
'
}

# Parse the command line
opt_forcemimicbuild=false
opt_allowroot=false
opt_skipmimicbuild=false
opt_python=python3
param=''

for var in "$@" ; do
    # Check if parameter should be read
    if [[ $param == 'python' ]] ; then
        opt_python=$var
        param=""
        continue
    fi

    # Check for options
    if [[ $var == '-h' || $var == '--help' ]] ; then
        show_help
        exit 0
    fi

    if [[ $var == '--clean' ]] ; then
        if clean_mycroft_files; then
            exit 0
        else
            exit 1
        fi
    fi
    

    if [[ $var == '-r' || $var == '--allow-root' ]] ; then
        opt_allowroot=true
    fi

    if [[ $var == '-fm' ]] ; then
        opt_forcemimicbuild=true
    fi
    if [[ $var == '-n' || $var == '--no-error' ]] ; then
        # Do NOT exit on errors
	set +Ee
    fi
    if [[ $var == '-sm' ]] ; then
        opt_skipmimicbuild=true
    fi
    if [[ $var == '-p' || $var == '--python' ]] ; then
        param='python'
    fi
done

if [[ $(id -u) -eq 0 && $opt_allowroot != true ]] ; then
    echo 'Este script não deve ser executado como root ou com sudo.'
    echo 'Se você realmente precisar fazer isso, execute novamente com --allow-root'
    exit 1
fi


function found_exe() {
    hash "$1" 2>/dev/null
}


if found_exe sudo ; then
    SUDO=sudo
elif found_exe doas ; then
    SUDO=doas
elif [[ $opt_allowroot != true ]]; then
    echo 'Este script requer "sudo" para instalar os pacotes do sistema. Instale-o e execute novamente este script.'
    exit 1
fi


function get_YN() {
    # Faça um loop até que o usuário pressione a tecla S ou N
    echo -e -n "Escolha [${CYAN}S${RESET}/${CYAN}N${RESET}]: "
    while true; do
        read -N1 -s key
        case $key in
        [Ss])
            return 0
            ;;
        [Nn])
            return 1
            ;;
        esac
    done
}

# Se tput estiver disponível e puder lidar com várias cores
if found_exe tput ; then
    if [[ $(tput colors) != "-1" && -z $CI ]]; then
        GREEN=$(tput setaf 2)
        BLUE=$(tput setaf 4)
        CYAN=$(tput setaf 6)
        YELLOW=$(tput setaf 3)
        RESET=$(tput sgr0)
        HIGHLIGHT=$YELLOW
    fi
fi

# Executa um assistente de configuração pela primeira vez que orienta o usuário em algumas decisões
if [[ ! -f .dev_opts.json && -z $CI ]] ; then
    echo "
$CYAN            Bem vindo ao a assistente Virtual EVA!  $RESET"
    sleep 0.5
    echo '
Este script foi desenvolvido para facilitar o trabalho com Mycroft. 
Durante esta primeira execução de dev_setup, 
faremos algumas perguntas para ajudar a configurar seu ambiente.'
    sleep 0.5
    # The AVX instruction set is an x86 construct
    # ARM has a range of equivalents, unsure which are (un)supported by TF.
    if ! grep -q avx /proc/cpuinfo && [[ ! $(uname -m) == 'arm'* ]]; then
      echo "
O Precise Wake Word Engine requer o conjunto de instruções AVX, 
que não é compatível com sua CPU. Você quer voltar para o mecanismo PocketSphinx? 
Os usuários avançados podem construir o mecanismo preciso com uma versão mais antiga do TensorFlow (v1.13) - se desejado -
 e alterar use_precise para true em mycroft.conf.
   S) Sim, desejo usar o mecanismo PocketSphinx ou o meu próprio.
   N) Não, pare a instalação."
        if get_YN ; then
            if [[ ! -f /etc/mycroft/mycroft.conf ]]; then
                $SUDO mkdir -p /etc/mycroft
                $SUDO touch /etc/mycroft/mycroft.conf
                $SUDO bash -c 'echo "{ \"use_precise\": false }" > /etc/mycroft/mycroft.conf'
            else
                # Ensure dependency installed to merge configs
                disable_precise_later=true
            fi
        else
            echo -e "$HIGHLIGHT N - quit the installation $RESET"
            exit 1
        fi
        echo
    fi
    echo "
Você quer rodar no nodo 'master' ou no modo dev (desenvolvimento)? 
A menos que você seja um desenvolvedor modificando o próprio mycroft-core, você deve executar no
ramo 'mestre'. Ele é atualizado duas vezes por semana com uma versão estável.
   S) Sim, execute no modo 'master' estável
   N) Não, eu quero executar no modo instável"
    if get_YN ; then
        echo -e "$HIGHLIGHT S - usando modo 'master' $RESET"
        branch=master
        git checkout ${branch}
    else
        echo -e "$HIGHLIGHT N - usando o modo instavel $RESET"
        branch=dev
    fi

    sleep 0.5
    echo "
EVA é desenvolvida ativamente e em constante evolução. 
É recomendado que você  a atualize regularmente. 
Você gostaria de atualizar automaticamente sempre que iniciar a EVA? 
Isso é altamente recomendado, especialmente para aqueles que executam no branch 'master'.
   Sim, verifique automaticamente se há atualizações
   Não, serei responsável por manter o EVA atualizado. "
    if get_YN ; then
        echo -e "$HIGHLIGHT S - alutalizar automaticamente $RESET"
        autoupdate=true
    else
        echo -e "$HIGHLIGHT N - atualizar manualmente utilizando 'git pull' $RESET"
        autoupdate=false
    fi

    #  Pull down mimic source?  Most will be happy with just the package
    if [[ $opt_forcemimicbuild == false && $opt_skipmimicbuild == false ]] ; then
        sleep 0.5
        echo '
EVA usa sua tecnologia Mimic para falar com você. 
O Mimic pode ser executado localmente e a partir de um servidor. 
O Mimic local é mais robótico, mas sempre disponível, independentemente da conectividade de rede. 
Ele agirá como um fallback se não puder entrar em contato com o servidor do Mimic.

No entanto, construir o Mimic local é demorado - pode levar horas em máquinas mais lentas. 
Isso pode ser ignorado, mas a EVA não conseguirá falar se você perder a conectividade de rede.
Você gostaria de construir o Mimic localmente? '
        if get_YN ; then
            echo -e "$HIGHLIGHT S - Mimic ser[a instalado $RESET"
        else
            echo -e "$HIGHLIGHT N - Mimic nao sera instalado  $RESET"
            opt_skipmimicbuild=true
        fi
    fi

    echo
    # Add mycroft-core/bin to the .bashrc PATH?
    sleep 0.5
    echo '
Existem vários comandos auxiliares EVA na pasta bin. Esses
pode ser adicionado ao PATH do seu sistema, tornando mais simples o uso do EVA.
Deseja que isso seja adicionado ao seu PATH no .profile? '
    if get_YN ; then
        echo -e "$HIGHLIGHT S - Adicionando comandos Mycroft ao seu PATH $RESET"

        if [[ ! -f ~/.profile_mycroft ]] ; then
            # Only add the following to the .profile if .profile_mycroft
            # doesn't exist, indicating this script has not been run before
            echo '' >> ~/.profile
            echo '# Adicionando comandos EVA ao seu PATH' >> ~/.profile
            echo 'source ~/.profile_mycroft' >> ~/.profile
        fi

        echo "
# AVISO: Este arquivo pode ser substituído no futuro, não o personalize.
# definir o caminho para que inclua utilitários EVA 
if [ -d \"${TOP}/bin\" ] ; then
    PATH=\"\$PATH:${TOP}/bin\"
fi" > ~/.profile_mycroft
        echo -e "Digite ${CYAN}mycroft-help$RESET para ver os comamdos dispon[iveis."
    else
        echo -e "$HIGHLIGHT N - PATH deixar inalterado $RESET"
    fi

    # Create a link to the 'skills' folder.
    sleep 0.5
    echo
    echo 'A localização padrão para habilidades de EVA esta em /opt/mycroft/skills.'
    if [[ ! -d /opt/mycroft/skills ]] ; then
        echo 'Este script criará essa pasta para você. Isso requer permissao sudo'
        echo 'permissão e pode pedir uma senha ...'
        setup_user=$USER
        setup_group=$(id -gn $USER)
        $SUDO mkdir -p /opt/mycroft/skills
        $SUDO chown -R ${setup_user}:${setup_group} /opt/mycroft
        echo 'Criado!'
    fi
    if [[ ! -d skills ]] ; then
        ln -s /opt/mycroft/skills skills
        echo "Por conveniência, um link simbólico foi criado chamado 'skills' que leva"
        echo 'skills /opt/mycroft/skills.'
    fi

    # Add PEP8 pre-commit hook
    sleep 0.5
    echo '
(Desenvolvedor) Você deseja verificar automaticamente o estilo do código ao enviar o código.
Se não tiver certeza, responda yes (sim).
'
    if get_YN ; then
        echo 'Irá instalar pré-confirmação PEP8 ...'
        INSTALL_PRECOMMIT_HOOK=true
    fi

    # Save options
    echo '{"use_branch": "'$branch'", "auto_update": '$autoupdate'}' > .dev_opts.json

    echo -e '\nParte interativa concluída, agora instalando dependências...\n'
    sleep 5
fi

function os_is() {
    [[ $(grep "^ID=" /etc/os-release | awk -F'=' '/^ID/ {print $2}' | sed 's/\"//g') == $1 ]]
}

function os_is_like() {
    grep "^ID_LIKE=" /etc/os-release | awk -F'=' '/^ID_LIKE/ {print $2}' | sed 's/\"//g' | grep -q "\\b$1\\b"
}

function redhat_common_install() {
    $SUDO yum install -y cmake gcc-c++ git python3-devel libtool libffi-devel openssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel libjpeg-devel fann-devel pulseaudio
    git clone https://github.com/libfann/fann.git
    cd fann
    git checkout b211dc3db3a6a2540a34fbe8995bf2df63fc9939
    cmake .
    $SUDO make install
    cd "$TOP"
    rm -rf fann

}

function debian_install() {
    APT_PACKAGE_LIST="git python3 python3-dev python3-setuptools libtool \
        libffi-dev libssl-dev autoconf automake bison swig libglib2.0-dev \
        portaudio19-dev mpg123 screen flac curl libicu-dev pkg-config \
        libjpeg-dev libfann-dev build-essential jq pulseaudio \
        pulseaudio-utils"

    if dpkg -V libjack-jackd2-0 > /dev/null 2>&1 && [[ -z ${CI} ]] ; then
        echo "
Detectamos que seu computador possui o pacote libjack-jackd2-0 instalado.
EVA requer um pacote conflitante e provavelmente desinstalará este pacote. 
Em alguns sistemas, isso pode fazer com que outros programas sejam marcados para remoção. 
Por favor, revise as seguintes alterações no pacote com atenção."
        read -p "Precione enter para continuar"
        $SUDO apt-get install $APT_PACKAGE_LIST
    else
        $SUDO apt-get install -y $APT_PACKAGE_LIST
    fi
}


function open_suse_install() {
    $SUDO zypper install -y git python3 python3-devel libtool libffi-devel libopenssl-devel autoconf automake bison swig portaudio-devel mpg123 flac curl libicu-devel pkg-config libjpeg-devel libfann-devel python3-curses pulseaudio
    $SUDO zypper install -y -t pattern devel_C_C++
}


function fedora_install() {
    $SUDO dnf install -y git python3 python3-devel python3-pip python3-setuptools python3-virtualenv pygobject3-devel libtool libffi-devel openssl-devel autoconf bison swig glib2-devel portaudio-devel mpg123 mpg123-plugins-pulseaudio screen curl pkgconfig libicu-devel automake libjpeg-turbo-devel fann-devel gcc-c++ redhat-rpm-config jq make
}


function arch_install() {
    $SUDO pacman -S --needed --noconfirm git python python-pip python-setuptools python-virtualenv python-gobject libffi swig portaudio mpg123 screen flac curl icu libjpeg-turbo base-devel jq pulseaudio pulseaudio-alsa

    pacman -Qs '^fann$' &> /dev/null || (
        git clone  https://aur.archlinux.org/fann.git
        cd fann
        makepkg -srciA --noconfirm
        cd ..
        rm -rf fann
    )
}


function centos_install() {
    $SUDO yum install epel-release
    redhat_common_install
}

function redhat_install() {
    $SUDO yum install -y wget
    wget https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    $SUDO yum install -y epel-release-latest-7.noarch.rpm
    rm epel-release-latest-7.noarch.rpm
    redhat_common_install

}

function gentoo_install() {
    $SUDO emerge --noreplace dev-vcs/git dev-lang/python dev-python/setuptools dev-python/pygobject dev-python/requests sys-devel/libtool virtual/libffi virtual/jpeg dev-libs/openssl sys-devel/autoconf sys-devel/bison dev-lang/swig dev-libs/glib media-libs/portaudio media-sound/mpg123 media-libs/flac net-misc/curl sci-mathematics/fann sys-devel/gcc app-misc/jq media-libs/alsa-lib dev-libs/icu
}

function alpine_install() {
    $SUDO apk add --virtual makedeps-mycroft-core alpine-sdk git python3 py3-pip py3-setuptools py3-virtualenv mpg123 vorbis-tools pulseaudio-utils fann-dev automake autoconf libtool pcre2-dev pulseaudio-dev alsa-lib-dev swig python3-dev portaudio-dev libjpeg-turbo-dev
}

function install_deps() {
    echo 'Instalando pacotes...'
    if found_exe zypper ; then
        # OpenSUSE
        echo "$GREEN Instalando pacotes para OpenSUSE...$RESET"
        open_suse_install
    elif found_exe yum && os_is centos ; then
        # CentOS
        echo "$GREEN Instalando pacotes para Centos...$RESET"
        centos_install
    elif found_exe yum && os_is rhel ; then
        # Redhat Enterprise Linux
        echo "$GREEN Instalando pacotes para Red Hat...$RESET"
        redhat_install
    elif os_is_like debian || os_is debian || os_is_like ubuntu || os_is ubuntu || os_is linuxmint; then
        # Debian / Ubuntu / Mint
        echo "$GREEN Instalando pacotes para Debian/Ubuntu/Mint...$RESET"
        debian_install
    elif os_is_like fedora || os_is fedora; then
        # Fedora
        echo "$GREEN Instalando pacotes para Fedora...$RESET"
        fedora_install
    elif found_exe pacman && (os_is arch || os_is_like arch); then
        # Arch Linux
        echo "$GREEN Instalando pacotes para Arch...$RESET"
        arch_install
    elif found_exe emerge && os_is gentoo; then
        # Gentoo Linux
        echo "$GREEN Instalando pacotes para Gentoo Linux ...$RESET"
        gentoo_install
    elif found_exe apk && os_is alpine; then
        # Alpine Linux
        echo "$GREEN Instalando pacotes para Alpine Linux...$RESET"
        alpine_install
    else
    	echo
        echo -e "${YELLOW}Não foi possível encontrar o gerenciador de pacotes
${YELLOW}Certifique-se de instalar manualmente:$BLUE git python3 python-setuptools python-venv pygobject libtool libffi libjpg openssl autoconf bison swig glib2.0 portaudio19 mpg123 flac curl fann g++ jq\n$RESET"

        echo 'Aviso: Falha ao instalar todas as dependências. Continuar? y/N'
        read -n1 continue
        if [[ $continue != 'y' ]] ; then
            exit 1
        fi

    fi
}

VIRTUALENV_ROOT=${VIRTUALENV_ROOT:-"${TOP}/.venv"}

function install_venv() {
    $opt_python -m venv "${VIRTUALENV_ROOT}/" --without-pip
    # Force version of pip for reproducability, but there is nothing special
    # about this version.  Update whenever a new version is released and
    # verified functional.
    curl https://bootstrap.pypa.io/get-pip.py | "${VIRTUALENV_ROOT}/bin/python" - 'pip==20.0.2'
    # Function status depending on if pip exists
    [[ -x ${VIRTUALENV_ROOT}/bin/pip ]]
}

install_deps

# Configure to use the standard commit template for
# this repo only.
git config commit.template .gitmessage

# Check whether to build mimic (it takes a really long time!)
build_mimic='n'
if [[ $opt_forcemimicbuild == true ]] ; then
    build_mimic='y'
else
    # first, look for a build of mimic in the folder
    has_mimic=''
    if [[ -f ${TOP}/mimic/bin/mimic ]] ; then
        has_mimic=$(${TOP}/mimic/bin/mimic -lv | grep Voice) || true
    fi

    # in not, check the system path
    if [[ -z $has_mimic ]] ; then
        if [[ -x $(command -v mimic) ]] ; then
            has_mimic=$(mimic -lv | grep Voice) || true
        fi
    fi

    if [[ -z $has_mimic ]]; then
        if [[ $opt_skipmimicbuild == true ]] ; then
            build_mimic='n'
        else
            build_mimic='y'
        fi
    fi
fi

if [[ ! -x ${VIRTUALENV_ROOT}/bin/activate ]] ; then
    if ! install_venv ; then
        echo 'Falha ao configurar o virtualenv para EVA, saindo da configuração.'
        exit 1
    fi
fi

# Start the virtual environment
source "${VIRTUALENV_ROOT}/bin/activate"
cd "$TOP"

# Install pep8 pre-commit hook
HOOK_FILE='./.git/hooks/pre-commit'
if [[ -n $INSTALL_PRECOMMIT_HOOK ]] || grep -q 'MYCROFT DEV SETUP' $HOOK_FILE; then
    if [[ ! -f $HOOK_FILE ]] || grep -q 'MYCROFT DEV SETUP' $HOOK_FILE; then
        echo 'Installing PEP8 check as precommit-hook'
        echo "#! $(which python)" > $HOOK_FILE
        echo '# MYCROFT DEV SETUP' >> $HOOK_FILE
        cat ./scripts/pre-commit >> $HOOK_FILE
        chmod +x $HOOK_FILE
    fi
fi

PYTHON=$(python -c "import sys;print('python{}.{}'.format(sys.version_info[0], sys.version_info[1]))")

# Add mycroft-core to the virtualenv path
# (This is equivalent to typing 'add2virtualenv $TOP', except
# you can't invoke that shell function from inside a script)
VENV_PATH_FILE="${VIRTUALENV_ROOT}/lib/$PYTHON/site-packages/_virtualenv_path_extensions.pth"
if [[ ! -f $VENV_PATH_FILE ]] ; then
    echo 'import sys; sys.__plen = len(sys.path)' > "$VENV_PATH_FILE" || return 1
    echo "import sys; new=sys.path[sys.__plen:]; del sys.path[sys.__plen:]; p=getattr(sys,'__egginsert',0); sys.path[p:p]=new; sys.__egginsert = p+len(new)" >> "$VENV_PATH_FILE" || return 1
fi

if ! grep -q "$TOP" $VENV_PATH_FILE ; then
    echo 'Adicionando mycroft-core para virtualenv path'
    sed -i.tmp '1 a\
'"$TOP"'
' "$VENV_PATH_FILE"
fi

# install required python modules
if ! pip install -r requirements/requirements.txt ; then
    echo 'Aviso: Falha ao instalar as dependências necessárias. Continuar? y/N'
    read -n1 continue
    if [[ $continue != 'y' ]] ; then
        exit 1
    fi
fi

# install optional python modules
if [[ ! $(pip install -r requirements/extra-audiobackend.txt) ||
	! $(pip install -r requirements/extra-stt.txt) ||
	! $(pip install -r requirements/extra-mark1.txt) ]] ; then
    echo 'Aviso: Falha ao instalar algumas dependências opcionais. Continuar? y/N'
    read -n1 continue
    if [[ $continue != 'y' ]] ; then
        exit 1
    fi
fi


if ! pip install -r requirements/tests.txt ; then
    echo "Aviso: os requisitos de teste não foram instalados. Nota: a operação normal ainda deve funcionar bem..."
fi

SYSMEM=$(free | awk '/^Mem:/ { print $2 }')
MAXCORES=$(($SYSMEM / 2202010))
MINCORES=1
CORES=$(nproc)

# ensure MAXCORES is > 0
if [[ $MAXCORES -lt 1 ]] ; then
    MAXCORES=${MINCORES}
fi

# Be positive!
if ! [[ $CORES =~ ^[0-9]+$ ]] ; then
    CORES=$MINCORES
elif [[ $MAXCORES -lt $CORES ]] ; then
    CORES=$MAXCORES
fi

echo "Construindo com  $CORES nucleos."

#build and install pocketsphinx
#build and install mimic

cd "$TOP"

if [[ $build_mimic == 'y' || $build_mimic == 'Y' ]] ; then
    echo 'AVISO: o comando seguinte pode levar muito tempo para ser executado!'
    "${TOP}/scripts/install-mimic.sh" " $CORES"
else
    echo 'Ignorando a construção de mímica.'
fi

# set permissions for common scripts
chmod +x start-mycroft.sh
chmod +x stop-mycroft.sh
chmod +x bin/mycroft-cli-client
chmod +x bin/mycroft-help
chmod +x bin/mycroft-mic-test
chmod +x bin/mycroft-msk
chmod +x bin/mycroft-msm
chmod +x bin/mycroft-pip
chmod +x bin/mycroft-say-to
chmod +x bin/mycroft-skill-testrunner
chmod +x bin/mycroft-speak

# create and set permissions for logging
if [[ ! -w /var/log/mycroft/ ]] ; then
    # Creating and setting permissions
    echo 'Criando diret[orio de log /var/log/mycroft/'
    if [[ ! -d /var/log/mycroft/ ]] ; then
        $SUDO mkdir /var/log/mycroft/
    fi
    $SUDO chmod 777 /var/log/mycroft/
fi

#Store a fingerprint of setup
md5sum requirements/requirements.txt requirements/extra-audiobackend.txt requirements/extra-stt.txt requirements/extra-mark1.txt requirements/tests.txt dev_setup.sh > .installed
