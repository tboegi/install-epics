#!/bin/sh

BASHRC=~/.bashrc
BASH_ALIAS_EPICS=~/.epics

#if $(echo "$EPICS_ROOT" | grep -q /usr/local); then
  FSUDO=sudo
#fi

CP="$FSUDO cp"
LN="$FSUDO ln"
MKDIR="$FSUDO mkdir"
MV="$FSUDO mv"
RM="$FSUDO rm"

export CP FSUDO LN MKDIR MV RM SUDO

#extensions top
EPICS_EXTENSIONS_TOP_VER=extensionsTop_20120904

export EPICS_ROOT EPICS_BASE EPICS_MODULES EPICS_BASE_VER EPICS_ROOT EPICS_DEBUG
export EPICS_EXT=${EPICS_ROOT}/extensions
#########################
#apt or yum or port
if uname -a | egrep "CYGWIN|MING" >/dev/null; then
  SUDO=
else
  SUDO=sudo
fi
APTGET=/bin/false
if type apt-get >/dev/null 2>/dev/null; then
  APTGET="$SUDO apt-get install"
fi
if type yum >/dev/null 2>/dev/null; then
  APTGET="$SUDO /usr/bin/yum install"
fi
# port (Mac Ports)
if test -x /opt/local/bin/port; then
  APTGET="$SUDO port install"
fi
export APTGET
#########################

create_soft_x_y() {
  dir=$1
  src=$2
  dst=$3
  echo dir=$dir create_soft_x_y "$@"
  export dir src dst
  (
    cd "$dir" &&
    linkdst=$(readlink $dst) || linkdst=""
    if ! test "$linkdst" || test "$linkdst" != "$src"; then
      # unlink, first as user, then as SUDO
      if test "$linkdst" != "$src"; then
        echo "$linkdst" != "$dst" &&
        echo PWD=$PWD $RM $dst &&
        $RM -f $dst &&
        echo PWD=$PWD $LN -s $src $dst &&
        $LN -s $src $dst || {
          echo >&2 can not link $src $dst
          exit 1
        }
      fi
    fi
  )
}


wget_or_curl()
{
  url=$1
  file=$2
  if test -e $file; then
    return;
  fi
  (
    echo cd $EPICS_DOWNLOAD &&
    cd $EPICS_DOWNLOAD &&
    if ! test -e $file; then
        if type curl >/dev/null 2>/dev/null; then
            curl "$url" >/tmp/"$file.$$.tmp" &&
              $MV "/tmp/$file.$$.tmp" "$file" || {
                echo >&2 curl can not get $url
                exit 1
              }
        else
          # We need wget
          if ! type wget >/dev/null 2>/dev/null; then
              echo $APTGET wget
              $APTGET wget
          fi &&
            wget "$url" -O "$file.$$.tmp" &&
            $MV "$file.$$.tmp" "$file" || {
              echo >&2 wget can not get $url
              exit 1
            }
        fi
      fi
  ) &&
  $LN -s $EPICS_DOWNLOAD/$file $file
}

#add package x when y is not there
addpacketifneeded() {
  needed=$1
  tobeinstalled=$2
  if test -z "$tobeinstalled"; then
    tobeinstalled=$needed
  fi
  if ! which $needed ; then
    echo $APTGET $tobeinstalled
    $APTGET $tobeinstalled
  fi
}

install_re2c()
{
  cd $EPICS_ROOT &&
  if ! test -d re2c-code-git; then
    git clone git://git.code.sf.net/p/re2c/code-git re2c-code-git.$$.tmp &&
    $MV re2c-code-git.$$.tmp  re2c-code-git
  fi &&
  (
    cd re2c-code-git/re2c &&
    addpacketifneeded automake &&
    ./autogen.sh &&
    ./configure &&
    make &&
    echo PWD=$PWD $FSUDO make install &&
    $FSUDO make install
  )
}
(
  # We need gcc and g++: gcc-g++ under Scientifc Linux
  if ! type g++ >/dev/null 2>/dev/null; then
    echo $APTGET gcc-c++
    $APTGET gcc-c++
  fi
  # We need g++
  if ! type g++ >/dev/null 2>/dev/null; then
    echo $APTGET g++
    $APTGET g++
  fi &&
  #We need readline
  # Mac OS: /usr/include/readline/readline.h
  # Linux: /usr/include/readline.h
  if ! test -r /usr/include/readline/readline.h; then
    test -r /usr/include/readline.h ||
    $APTGET readline-devel ||
    $APTGET libreadline-dev ||
    {
      echo >&2 can not install readline-devel
      exit 1
    }
  fi
) &&

if ! type re2c >/dev/null 2>/dev/null; then
  echo $APTGET re2c
  $APTGET re2c || install_re2c
fi &&

echo OK || {
  echo >&2 failed PWD=$PWD
  exit 1
}

