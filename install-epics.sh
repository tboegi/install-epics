#!/bin/sh

BASHRC=~/.bashrc
BASH_ALIAS_EPICS=~/.epics

#Where is the source code of EPICS
HOME_EPICS_APPS=$HOME/../epics/Apps

#Where are the binaries of EPICS
EPICS_ROOT=/usr/local/epics
EPICS_BASE=$EPICS_ROOT/base
EPICS_MODULES=$EPICS_ROOT/modules

#Version of base
EPICS_BASE_VER=3.14.12.3

#Version for ASYN
ASYNVER=asyn4-22

#Version for synApps
SYNAPPSVER=synApps_5_6

#extensions top
EPICS_EXTENSIONS_TOP_VER=extensionsTop_20120904

#msi
EPICS_MSI_VER=msi1-5

export EPICS_ROOT EPICS_BASE EPICS_MODULES EPICS_BASE_VER HOME_EPICS_APPS
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

if ! test -d $HOME_EPICS_APPS; then
  $SUDO mkdir -p $HOME_EPICS_APPS || {
    echo >&2 can not chown $HOME_EPICS_APPS
    exit 1
  }
fi

if ! test -w $HOME_EPICS_APPS; then
  $SUDO chown "$USER" $HOME_EPICS_APPS || {
    echo >&2 can not chown $HOME_EPICS_APPS
    exit 1
  }
fi

if test -L $EPICS_ROOT; then
  (
    cd /usr/local &&
    epicsbaselink=$(readlink epics) &&
    #echo epicsbaselink=$epicsbaselink
    if test "$epicsbaselink" != "$HOME_EPICS_APPS"; then
      echo "$epicsbaselink" != "$HOME_EPICS_APPS" &&
      echo $SUDO rm $HOME_EPICS_APPS &&
      $SUDO rm $PWD/epics &&
      echo $SUDO ln -s $HOME_EPICS_APPS epics &&
      $SUDO ln -s $HOME_EPICS_APPS epics || {
        echo >&2 can not unlink $HOME_EPICS_APPS
        exit 1
      }
    fi
  )
else
  if test -e $EPICS_ROOT; then
    echo >&2 $EPICS_ROOT not a softlink
    echo >&2 $EPICS_ROOT please remove it
    exit 1
  fi
  cd /usr/local &&
  echo $SUDO ln -s $HOME_EPICS_APPS epics &&
  $SUDO ln -s $HOME_EPICS_APPS epics || {
    echo >&2 can not unlink $HOME_EPICS_APPS
    exit 1
  }
fi


install_re2c()
{
  cd $HOME_EPICS_APPS &&
  if ! test -d re2c-code-git; then
    git clone git://git.code.sf.net/p/re2c/code-git re2c-code-git.tmp.$$ &&
    mv re2c-code-git.tmp.$$  re2c-code-git
  fi &&
  (
    cd re2c-code-git/re2c &&
    ./autogen.sh &&
    ./configure &&
    make &&
    echo PWD=$PWD $SUDO make install &&
    $SUDO make install
  )
}


(
  cd $HOME_EPICS_APPS &&
  if ! test -e baseR${EPICS_BASE_VER}.tar.gz; then
    wget http://www.aps.anl.gov/epics/download/base/baseR${EPICS_BASE_VER}.tar.gz -O baseR${EPICS_BASE_VER}.tar.gz.$$ &&
    mv baseR${EPICS_BASE_VER}.tar.gz.$$ baseR${EPICS_BASE_VER}.tar.gz || {
      echo >&2 can not wget baseR${EPICS_BASE_VER}.tar.gz
      exit 1
    }
  fi
  if ! test -d base-$EPICS_BASE_VER; then
    tar xzf baseR${EPICS_BASE_VER}.tar.gz || {
      echo >&2 can not tar xzf baseR${EPICS_BASE_VER}.tar.gz
      rm -rf base-$EPICS_BASE_VER
      exit 1
    }
  fi &&
  if ! test -L base; then
    echo ln -s ./base-${EPICS_BASE_VER} ./base &&
    ln -s ./base-${EPICS_BASE_VER} ./base || {
      echo >&2 can not tar xzf baseR${EPICS_BASE_VER}.tar.gz
      exit 1
    }
  fi
) || exit 1

EPICS_HOST_ARCH=$($EPICS_ROOT/base/startup/EpicsHostArch) || {
  echo >&2 EPICS_HOST_ARCH failed
  exit 1
}
# here we know the EPICS_HOST_ARCH
EPICS_BASE_BIN=${EPICS_BASE}/bin/$EPICS_HOST_ARCH
EPICS_EXT_BIN=${EPICS_EXT}/bin/$EPICS_HOST_ARCH
PATH=$PATH:$EPICS_BASE_BIN:$EPICS_EXT_BIN
EPICS_EXT_LIB=${EPICS_EXT}/lib/$EPICS_HOST_ARCH
if test "${LD_LIBRARY_PATH}"; then
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$EPICS_BASE_LIB
else
  export LD_LIBRARY_PATH=$EPICS_EXT_LIB
fi
echo PATH=$PATH
export EPICS_BASE_BIN EPICS_EXT EPICS_EXT_LIB EPICS_EXT_BIN PATH LD_LIBRARY_PATH
############# Fix bashrc (or friends)

if ! grep "$BASH_ALIAS_EPICS" $BASHRC >/dev/null; then
  echo updating $BASHRC
  cat <<EOF >>$BASHRC
#install-epics.sh
if test -r ${BASH_ALIAS_EPICS}; then
. ${BASH_ALIAS_EPICS}
fi
EOF
fi

if ! test -e ${BASH_ALIAS_EPICS}; then
  echo creating en empty ${BASH_ALIAS_EPICS}
  touch ${BASH_ALIAS_EPICS}
fi

if ! grep EPICS_EXT_LIB ${BASH_ALIAS_EPICS} >/dev/null; then
  echo updating ${BASH_ALIAS_EPICS}
  cat >>${BASH_ALIAS_EPICS} <<EOF
export EPICS_ROOT=$EPICS_ROOT
export EPICS_BASE=\$EPICS_ROOT/base
export EPICS_EXT=\${EPICS_ROOT}/extensions
export EPICS_HOST_ARCH=$($EPICS_BASE/startup/EpicsHostArch)
export EPICS_EXT_BIN=${EPICS_EXT}/bin/\$EPICS_HOST_ARCH
export EPICS_EXT_LIB=${EPICS_EXT}/lib/\$EPICS_HOST_ARCH
export EPICS_MODULES=\$EPICS_ROOT/modules
export EPICS_BASE_BIN=\${EPICS_BASE}/bin/\$EPICS_HOST_ARCH
export EPICS_BASE_LIB=\${EPICS_BASE}/lib/\$EPICS_HOST_ARCH
export LD_LIBRARY_PATH=\${EPICS_BASE_LIB}:\$LD_LIBRARY_PATH
if test "\$LD_LIBRARY_PATH"; then
  export LD_LIBRARY_PATH=\$LD_LIBRARY_PATH:\$EPICS_BASE_LIB
else
  export LD_LIBRARY_PATH=\$EPICS_EXT_LIB
fi
export PATH=\$PATH:\$EPICS_BASE_BIN:\$EPICS_EXT_BIN
EOF
fi
################

if ! test -e $HOME_EPICS_APPS/base/makeok; then
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
  (
    echo make in $HOME_EPICS_APPS/base &&
    cd $HOME_EPICS_APPS/base &&
    make && touch makeok || {
      echo >&2 make failed in $PWD
      exit 1
    }
  ) || exit 1
else
  echo The file $HOME_EPICS_APPS/base/makeok exist, skipping make
fi

#Modules
(
  cd $HOME_EPICS_APPS/ &&
  if ! test -d modules; then
    mkdir modules
  fi
) || exit 1


#synApps
if test -n "$SYNAPPSVER"; then
  (
    cd $HOME_EPICS_APPS &&
    if ! test -e $SYNAPPSVER.tar.gz; then
      wget http://www.aps.anl.gov/bcda/synApps/tar/$SYNAPPSVER.tar.gz -O $SYNAPPSVER.tar.gz.$$ &&
      mv $SYNAPPSVER.tar.gz.$$ $SYNAPPSVER.tar.gz || {
        echo >&2 can not wget $SYNAPPSVER.tar.gz
        exit 1
      }
    fi &&
    if ! test -d $SYNAPPSVER; then
      tar xzvf $SYNAPPSVER.tar.gz
    fi
  ) || {
    echo >&2 failed tar xzvf $SYNAPPSVER.tar.gz in $PWD
    exit 1
  } &&
  (
    cd $HOME_EPICS_APPS/synApps_5_6/support/configure &&
    (
      if ! test -e RELEASE.orig; then
        cp -v RELEASE RELEASE.orig || exit 1
      fi &&
      sed <RELEASE.orig >/tmp/$$ \
        -e "s!^SUPPORT=.*!SUPPORT=$EPICS_ROOT/synApps_5_6/support!" \
        -e "s!^EPICS_BASE=.*!EPICS_BASE=$EPICS_ROOT/base!" &&
      mv -fv /tmp/$$ RELEASE
    ) || {
      echo >&2 failed RELEASE in $PWD
      exit 1
    } &&
    (
      mkdir -p orig || {
        echo >&2 failed mkdir -p orig in $PWD
        exit 1
      }
      for f in EPICS_BASE.cygwin-x86 EPICS_BASE.linux-x86 EPICS_BASE.linux-x86_64 EPICS_BASE.win32-x86 EPICS_BASE.windows-x64 SUPPORT.cygwin-x86  SUPPORT.linux-x86  SUPPORT.linux-x86_64  SUPPORT.win32-x86  SUPPORT.windows-x64; do
        if test -e "$f"; then
          mv -v "$f" $PWD/orig/ || {
            echo >&2 failed mv "$f" orig/ in $PWD
            exit 1
          }
        fi
      done
    ) &&
    (
      echo cd $HOME_EPICS_APPS/synApps_5_6/support &&
      cd $HOME_EPICS_APPS/synApps_5_6/support &&
      if ! test -e makereleaseok; then
        make release && touch makereleaseok || {
          echo >&2 failed make release in $PWD
          exit 1
        }
      else
        echo The file $PWD/makereleaseok exist, skipping make release
      fi
      if ! test -e Makefile.orig; then
        cp -v Makefile Makefile.orig || exit 1
      fi &&
      cp -v Makefile.orig Makefile &&
      for mod in ALLEN_BRADLEY DAC128V IP330 IPUNIDIG LOVE IP VAC SOFTGLUE QUADEM DELAYGEN CAMAC VME AREA_DETECTOR DXP; do
        echo removing $mod in $PWD/Makefile &&
        sed -e "s/ $mod / /g" -e "s/ $mod\$/ /g" <Makefile >Makefile.tmp.$$ &&
        ! diff Makefile Makefile.tmp.$$ >/dev/null &&
        mv -f Makefile.tmp.$$ Makefile ||{
          echo >&2 failed removing $mod in $PWD
          exit 1
        }
      done &&
      (
        # Remove AREA_DETECTOR and IP from RELEASE
        cd xxx-5-6/configure &&
        if ! test -e RELEASE.orig; then
          cp -v RELEASE RELEASE.orig || exit 1
        fi &&
        sed <RELEASE.orig >RELEASE.tmp.$$ \
          -e "s!^AREA_DETECTOR!#AREA_DETECTOR!" \
          -e "s!^IP=!#IP=!" &&
        mv -fv RELEASE.tmp.$$ RELEASE
      ) &&
      (
        # Remove AREA_DETECTOR and IP from dbd
        cd xxx-5-6/xxxApp/src &&
        if ! test -e xxxCommonInclude.dbd.orig; then
          cp -v xxxCommonInclude.dbd xxxCommonInclude.dbd.orig || exit 1
        fi &&
        sed <xxxCommonInclude.dbd.orig >xxxCommonInclude.dbd.tmp.$$ \
          -e "s!\(include.*ipSupport.dbd\)!#\1!" &&
        mv -fv xxxCommonInclude.dbd.tmp.$$ xxxCommonInclude.dbd
      ) &&
      (
        # Remove AREA_DETECTOR related modules from Makefile
        cd xxx-5-6/xxxApp/src &&
        if ! test -e Makefile.orig; then
          cp -v Makefile Makefile.orig || exit 1
        fi &&
        cp Makefile.orig Makefile &&
        for mod in ADSupport NDPlugin simDetector netCDF dxp "xxx_Common_LIBS += ip"; do
          echo removing $mod in $PWD/Makefile &&
          sed -e "s/\(.*$mod.*\)/#XXX Removed by install-epics.sh XXX  \1/g" <Makefile >Makefile.tmp.$$ &&
          ! diff Makefile Makefile.tmp.$$ >/dev/null &&
          mv -f $PWD/Makefile.tmp.$$ $PWD/Makefile ||{
            echo >&2 failed removing $mod in $PWD
            exit 1
          }
        done
      )
    ) || {
      echo >&2 failed in $PWD
      exit 1
    } &&
    (
      cd $HOME_EPICS_APPS/modules &&
      if ! test -d motor; then
        ln -sv ../synApps_5_6/support/motor-6-7/ motor || {
        echo >&2 Can not ln -sv ../synApps_5_6/support/motor-6-7/ motor
        exit 1
      }
      fi
    )
  ) || {
    echo >&2 failed RELEASE in $PWD
    exit 1
  }
  if test "$EPICS_EXTENSIONS_TOP_VER"; then
    (
      cd $HOME_EPICS_APPS &&
      if ! test -e $EPICS_EXTENSIONS_TOP_VER.tar.gz; then
        echo installing $EPICS_EXTENSIONS_TOP_VER &&
        wget http://www.aps.anl.gov/epics/download/extensions/$EPICS_EXTENSIONS_TOP_VER.tar.gz -O $EPICS_EXTENSIONS_TOP_VER.tar.gz.$$ &&
        mv $EPICS_EXTENSIONS_TOP_VER.tar.gz.$$ $EPICS_EXTENSIONS_TOP_VER.tar.gz || {
          echo >&2 can not wget $EPICS_EXTENSIONS_TOP_VER.tar.gz
          exit 1
        }
      fi
      if ! test -d ${EPICS_EXTENSIONS_TOP_VER}; then
        tar xzf $EPICS_EXTENSIONS_TOP_VER.tar.gz
      fi
    )
  fi &&
  if ! type re2c >/dev/null 2>/dev/null; then
    echo $APTGET re2c
    $APTGET re2c || install_re2c
  fi &&
  if test "$EPICS_MSI_VER"; then
    (
      cd $HOME_EPICS_APPS &&
      if ! test -e $EPICS_MSI_VER.tar.gz; then
        echo installing $EPICS_MSI_VER &&
        wget http://www.aps.anl.gov/epics/download/extensions/$EPICS_MSI_VER.tar.gz -O $EPICS_MSI_VER.tar.gz.$$ &&
        mv $EPICS_MSI_VER.tar.gz.$$ $EPICS_MSI_VER.tar.gz || {
          echo >&2 can not wget $EPICS_MSI_VER.tar.gz
          exit 1
        }
      fi &&
      if ! test -e extensions/src/$EPICS_MSI_VER/makeok; then
        (
          mkdir -p extensions/src &&
          cd extensions/src &&
          tar xzf ../../$EPICS_MSI_VER.tar.gz &&
          cd $EPICS_MSI_VER &&
          make && touch makeok || {
            echo >&2 make failed in $PWD
            exit 1
          }
        ) || {
          echo >&2 msi failed in $PWD
          exit 1
        }
      else
        echo The file extensions/src/$EPICS_MSI_VER/makeok exist, skipping make
      fi
    )
  fi &&
  (
    echo cd $HOME_EPICS_APPS/synApps_5_6/support
    cd $HOME_EPICS_APPS/synApps_5_6/support &&

    if ! test -e makeok; then
      make release || {
        echo >&2 PWD=$PWD failed make release
        exit 1
      }
      make rebuild && touch makeok || {
        echo >&2 PWD=$PWD failed make rebuild
        echo >&2 PATH=$PATH
        exit 1
      }
    else
      echo The file $PWD/makeok exist, skipping make
    fi
  ) || {
    echo >&2 failed $SYNAPPSVER PWD=$PWD PATH=$PATH
    exit 1
  }
else
  echo SYNAPPSVER not defined, skipping synApps
fi

if test -n "$ASYNVER"; then
  (
    cd $HOME_EPICS_APPS/modules &&
    if ! test -d asyn; then
      ln -sv  ../asyn4-22/ asyn || {
        echo >&2 Can not ln -sv ../asyn4-22/ asyn
        exit 1
      }
    fi
  ) &&
  (
    cd $HOME_EPICS_APPS &&
    if ! test -e $ASYNVER.tar.gz; then
      wget http://www.aps.anl.gov/epics/download/modules/$ASYNVER.tar.gz -O $ASYNVER.tar.gz.$$ &&
      mv $ASYNVER.tar.gz.$$ $ASYNVER.tar.gz || {
        echo >&2 can not wget $ASYNVER.tar.gz
        exit 1
      }
    fi
    if ! test -d $ASYNVER; then
      tar xzvf $ASYNVER.tar.gz
    fi
  ) &&
  (
    cd $HOME_EPICS_APPS/$ASYNVER/configure && {
      if ! test -e RELEASE.orig; then
        cp -v RELEASE RELEASE.orig
      fi
      sed <RELEASE.orig >/tmp/$$ \
        -e "s!^EPICS_BASE=.*!EPICS_BASE=$EPICS_ROOT/base!" \
        -e 's!^IPAC=!#IPAC=!' \
        -e 's!^SNCSEQ=!#SNCSEQ=!' &&
      mv -vf /tmp/$$ RELEASE
    }
  ) &&
  (
    if ! test -e $HOME_EPICS_APPS/$ASYNVER/makeok; then
      (
        cd $HOME_EPICS_APPS/$ASYNVER &&
        make && touch makeok  || {
          echo >&2 make failed in $PWD
          exit 1
        }
      )
    else
      echo The file $HOME_EPICS_APPS/$ASYNVER/makeok exist, skipping make
    fi
  ) || {
    echo >&2 failed $ASYNVER
    exit 1
  }
else
  echo ASYNVER not defined, skipping asyn
fi
