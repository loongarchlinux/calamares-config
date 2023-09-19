#!/usr/bin/env bash

# New version of cleaner_script
# Made by @fernandomaroto and @manuel
# Any failed command will just be skipped, error message may pop up but won't crash the install process
# Net-install creates the file /tmp/run_once in live environment (need to be transfered to installed system) so it can be used to detect install option
# ISO-NEXT specific cleanup removals and additions (08-2021) @killajoe and @manuel
# 01-2022 passing in online and username as params - @dalto
# 04-2022 small code re-organization - @manuel
# 10-2022 remove unused code and support for dracut/mkinitcpio switch

_c_c_s_msg() {            # use this to provide all user messages (info, warning, error, ...)
    local type="$1"
    local msg="$2"
    echo "==> $type: $msg"
}

_pkg_msg() {            # use this to provide all package management messages (install, uninstall)
    local op="$1"
    local pkgs="$2"
    case "$op" in
        remove | uninstall) op="uninstalling" ;;
        install) op="installing" ;;
    esac
    echo "==> $op $pkgs"
}

_check_internet_connection(){
    eos-connection-checker
}

_is_pkg_installed() {  # this is not meant for offline mode !?
    # returns 0 if given package name is installed, otherwise 1
    local pkgname="$1"
    pacman -Q "$pkgname" >& /dev/null
}

_remove_a_pkg() {
    local pkgname="$1"
    _pkg_msg remove "$pkgname"
    pacman -Rsn --noconfirm "$pkgname"
}

_remove_pkgs_if_installed() {  # this is not meant for offline mode !?
    # removes given package(s) and possible dependencies if the package(s) are currently installed
    local pkgname
    local removables=()
    for pkgname in "$@" ; do
        if _is_pkg_installed "$pkgname" ; then
            _pkg_msg remove "$pkgname"
            removables+=("$pkgname")
        fi
    done
    if [ -n "$removables" ] ; then
        pacman -Rs --noconfirm "${removables[@]}"
    fi
}

_install_needed_packages() {
    if eos-connection-checker ; then
        _pkg_msg install "if missing: $*"
        pacman -S --needed --noconfirm "$@"
    else
        _c_c_s_msg warning "no internet connection, cannot install packages $*"
    fi
}

_set_im_method_env() {
    if _is_pkg_installed "fcitx5" ; then
        cat >> /etc/environment << EOF
XMODIFIERS=@im=fcitx
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
SDL_IM_MODULE=fcitx
EOF
    fi
}

##################################################################
# Virtual machine stuff.
# For virtual machines we assume internet connection exists.
##################################################################
_is_offline_mode() {
    if [ "$INSTALL_TYPE" = "online" ] ; then
        return 1           # online install mode
    else
        return 0           # offline install mode
    fi
}
_is_online_mode() { ! _is_offline_mode ; }

_remove_broadcom_wifi_driver() {
    local pkgname=broadcom-wl-dkms
    local file=/tmp/$pkgname.txt
    if [ "$(cat $file 2>/dev/null)" = "no" ] ; then
        _remove_a_pkg $pkgname
    fi
}

_install_more_firmware() {
    # Install possibly missing firmware packages based on detected hardware

    if [ -n "$(lspci -k | grep "Kernel driver in use: mwifiex_pcie")" ] ; then    # e.g. Microsoft Surface Pro
        _install_needed_packages linux-firmware-marvell
    fi
}

_run_if_exists_or_complain() {
    local app="$1"

    if (which "$app" >& /dev/null) ; then
        _c_c_s_msg info "running $*"
        "$@"
    else
        _c_c_s_msg warning "program $app not found."
    fi
}

_RunUserCommands() {
    local usercmdfile=/tmp/user_commands.bash
    if [ -r $usercmdfile ] ; then
        _c_c_s_msg info "running script $(basename $usercmdfile)"
        bash $usercmdfile $NEW_USER
    fi
}

_misc_cleanups() {
    # /etc/resolv.conf.pacnew may be unnecessary, so delete it

    local file=/etc/resolv.conf.pacnew
    if [ -z "$(grep -Pv "^[ ]*#" $file 2>/dev/null)" ] ; then
        _c_c_s_msg info "removing file $file"
        rm -f $file                                            # pacnew contains only comments
    fi
}

_clean_up(){
    local xx

    # remove broadcom-wl-dkms if it is not needed
    _remove_broadcom_wifi_driver

    _install_more_firmware

    _misc_cleanups

    # change log file permissions
    [ -r /var/log/Calamares.log ] && chown root:root /var/log/Calamares.log

    # run possible user-given commands
    _RunUserCommands
}

_show_info_about_installed_system() {
    local cmd
    local cmds=( "lsblk -f -o+SIZE"
                 "fdisk -l"
               )

    for cmd in "${cmds[@]}" ; do
        _c_c_s_msg info "$cmd"
        $cmd
    done
}

_run_hotfix_end() {
    local file=hotfix-end.bash
    local type=""
    if ! _check_internet_connection ; then
        _is_offline_mode && type=info || type=warning
        _c_c_s_msg $type "cannot fetch $file, no connection."
        return
    fi
    local url=$(eos-github2gitlab https://raw.githubusercontent.com/endeavouros-team/ISO-hotfixes/main/$file)
    wget --timeout=60 -q -O /tmp/$file $url && {
        _c_c_s_msg info "running script $file"
        bash /tmp/$file
    }
}

Main() {
    local filename=chrooted_cleaner_script.sh

    _c_c_s_msg info "$filename started."

    local i
    local NEW_USER="" INSTALL_TYPE="" BOOTLOADER=""

    # parse the options
    for i in "$@"; do
        case $i in
            --user=*)
                NEW_USER="${i#*=}"
                shift
                ;;
            --online)
                INSTALL_TYPE="online"
                shift
                ;;
            --bootloader=*)
                BOOTLOADER="${i#*=}"
                ;;
        esac
    done
    if [ -z "$NEW_USER" ] ; then
        _c_c_s_msg error "new username is unknown!"
    fi

    _clean_up
    _run_hotfix_end
    _show_info_about_installed_system
    _set_im_method_env

    # Remove pacnew files
    find /etc -type f -name "*.pacnew" -exec rm {} \;

    rm -rf /etc/calamares /opt/extra-drivers
    _c_c_s_msg info "$filename done."
}


########################################
########## SCRIPT STARTS HERE ##########
########################################

Main "$@"
