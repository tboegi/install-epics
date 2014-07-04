#!/bin/sh

BASHRC=~/.bashrc
BASH_ALIAS_EPICS=~/.epics

#Where is the source code of EPICS
if test -z "$HOME_EPICS_APPS"; then
  HOME_EPICS_APPS=$HOME/../epics/Apps
fi

#Where are the binaries of EPICS
EPICS_ROOT=/usr/local/epics
EPICS_BASE=$EPICS_ROOT/base
EPICS_MODULES=$EPICS_ROOT/modules

#Version of base
EPICS_BASE_VER=3.14.12.3

#Version for synApps
SYNAPPSVER=synApps_5_6

#Version for ASYN
ASYNVER=asyn4-22

if test $SYNAPPSVER=synApps_5_6; then
  MODSTOBEREMOVED="ALLEN_BRADLEY DAC128V IP330 IPUNIDIG LOVE IP VAC SOFTGLUE QUADEM DELAYGEN CAMAC VME AREA_DETECTOR DXP"
else
  MODSTOBEREMOVED="ALLEN_BRADLEY AREA_DETECTOR AUTOSAVE CAMAC DAC128V DXP DELAYGEN IP IP330 IPUNIDIG LOVE MCA MEASCOMP OPTICS QUADEM SOFTGLUE STD SNCSEQ VAC VME"
fi

#extensions top
EPICS_EXTENSIONS_TOP_VER=extensionsTop_20120904

#msi
EPICS_MSI_VER=msi1-5

#StreamDevice, later version than synApps
#STREAMDEVICEVER=StreamDevice-2-6

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
  echo $SUDO mkdir -p $HOME_EPICS_APPS &&
  $SUDO mkdir -p $HOME_EPICS_APPS || {
    echo >&2 can not chown $HOME_EPICS_APPS
    exit 1
  }
fi

if ! test -w $HOME_EPICS_APPS; then
  echo $SUDO chown "$USER" $HOME_EPICS_APPS &&
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
    git clone git://git.code.sf.net/p/re2c/code-git re2c-code-git.$$.tmp &&
    mv re2c-code-git.$$.tmp  re2c-code-git
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
run_make_in_dir()
{
  dir=$1 &&
  echo cd $dir &&
  (
    cd $dir &&
    make
  )
}

install_asyn_ver()
{
  asyndir="$1"/
  cd $HOME_EPICS_APPS/modules &&
  if test -L asyn; then
    echo rm asyn &&
    rm asyn
  fi &&
  ln -sv $asyndir asyn || {
    echo >&2 Can not ln -sv $asyndir asyn
    exit 1
  }
}

patch_motor_h()
{
  (
    cd "$1" &&
    if grep "epicsEndian.h" motor.h >/dev/null; then
      echo PWD=$PWD patch motor.h not needed &&
      return
    fi &&
      cat <<EOF >motor.diff
diff --git a/motorApp/MotorSrc/motor.h b/motorApp/MotorSrc/motor.h
--- a/motorApp/MotorSrc/motor.h
+++ b/motorApp/MotorSrc/motor.h
63a64
> #include <epicsEndian.h>
140c141
< #elif (CPU == PPC604) || (CPU == PPC603) || (CPU==PPC85XX) || (CPU == MC68040) || (CPU == PPC32)
---
> #elif defined(CPU) && ((CPU == PPC604) || (CPU == PPC603) || (CPU == PPC85XX) || (CPU == MC68040) || (CPU == PPC32))
141a143,148
> #elif defined(__GNUC__)
>     #if (EPICS_BYTE_ORDER == EPICS_ENDIAN_LITTLE)
>         #define LSB_First (TRUE)
>     #else
>         #define MSB_First (TRUE)
>     #endif
EOF
      echo PWD=$PWD patch motor.h &&
      if ! test -e motor.h.original; then
        cp motor.h motor.h.original
      fi &&
      cp motor.h.original motor.h &&
      patch <motor.diff
  )
}

install_motor()
{
  cd $HOME_EPICS_APPS/modules &&
  if test -e motor; then
    echo rm -rf motor &&
    rm -rf motor
  fi &&
  mkdir -p motor &&
  cd motor &&
  motordevver=$(echo ../../$SYNAPPSVER/support/motor-*) &&
  echo motordevver=$motordevver &&
  for f in src dbd Db lib include; do
    if test -e $f; then
      echo rm -rf $f &&
      rm -rf $f
    fi
  done &&
  (
    mkdir dbd &&
    cd dbd &&
    rm -rf * &&
    for mdbd in $(find ../../../$SYNAPPSVER/support/motor-* -name '*.dbd'); do
      dbdbasename="${mdbd##*/}" &&
      #echo mdbd=$mdbd dbdbasename=$dbdbasename &&
      if ! test -f $dbdbasename; then
        cp -fv $mdbd $dbdbasename
      fi
    done
  ) &&
  (
    mkdir Db &&
    cd Db &&
    rm -rf * &&
    for mdbd in $(find ../../../$SYNAPPSVER/support/motor-* -name '*.db'); do
      dbdbasename="${mdbd##*/}" &&
      #echo mdbd=$mdbd dbdbasename=$dbdbasename &&
      if ! test -f $dbdbasename; then
        cp -fv $mdbd $dbdbasename
      fi
    done
  ) &&
  (
    motorlib=$(find ../../$SYNAPPSVER/support/motor-*/ -name lib);
    echo motorlib=$motorlib
    ln -s "$motorlib"/ lib
  ) &&
  (
    motorinclude=$(find ../../$SYNAPPSVER/support/motor-*/ -name include);
    echo motorinclude=$motorinclude
    ln -s "$motorinclude"/ include
  )
}

install_streamdevice()
{
  cd $HOME_EPICS_APPS/modules &&
  if ! test -d streamdevice; then
    mkdir -p streamdevice
  fi &&
  cd streamdevice &&
  streamdevver=$(echo ../../$SYNAPPSVER/support/stream-*) &&
  echo streamdevver=$streamdevver &&
  if test -L src; then
    echo rm src &&
    rm src
  fi &&
  echo ln -s ../../$SYNAPPSVER/support/$streamdevver/streamDevice/src/ src &&
  ln -s ../../$SYNAPPSVER/support/$streamdevver/streamDevice/src/ src || exit 1
  for f in dbd lib include; do
    if test -L $f; then
      echo rm $f &&
      rm $f
    fi &&
    ln -s ../../$SYNAPPSVER/support/$streamdevver/$f/ $f || exit 1
  done
}


fix_epics_base()
{
  file="$1" &&
  if test -e "$file"; then
    filebasename="${file%*.original}" &&
    echo fix_epics_base PWD=$PWD file=$file filebasename=$filebasename &&
    if ! test -f "$filebasename.original"; then
      cp "$file" "$filebasename.original" || {
        echo >&2 failed cp -v $file $filebasename.original in $PWD
        exit 1
      }
    fi &&
    sed <"$filebasename.original" >"$file.$$.tmp" \
      -e "s!^SUPPORT=.*!SUPPORT=$EPICS_ROOT/$SYNAPPSVER/support!" \
      -e "s!^EPICS_BASE=.*!EPICS_BASE=$EPICS_ROOT/base!" \
      -e "s!^\(IPAC=.*\)!## rem by install-epics \1!" \
      -e "s!^\(SNCSEQ=.*\)!## rem by install-epics \1!" \
      -e "s!^BUSY=.*!BUSY=\$(SUPPORT)/busy-1-4!" &&
      mv -fv "$file.$$.tmp" "$file" &&
      if test "$ASYNVER"; then
        sed <"$file" >"$file.$$.tmp" \
          -e "s!^ASYN=.*!ASYN=$EPICS_MODULES/asyn!" &&
        mv -fv "$file.$$.tmp" "$file"
    fi
  else
    echo fix_epics_base PWD=$PWD file=$file does not exist, doing nothing
  fi
}


remove_modules_from_RELEASE()
{
  file="$1" &&
  for mod in $MODSTOBEREMOVED; do
    echo removing $mod in $PWD/$file &&
    if grep $mod $file >/dev/null; then
      sed -e "s/\($mod=.*\$\)/## xx \1/g" <$file >$file.$$.tmp &&
      ! diff $file $file.$$.tmp >/dev/null &&
      mv -f $file.$$.tmp $file || {
        echo >&2 failed removing $mod in $PWD
        exit 1
      }
    fi
  done
}

remove_modules_from_Makefile()
{
  file="$1" &&
  for mod in $MODSTOBEREMOVED; do
    echo removing $mod in $PWD/$file &&
    sed -e "s/ $mod / /g" -e "s/ $mod\$/ /g" <$file >$file.$$.tmp &&
    ! diff $file $file.$$.tmp >/dev/null &&
    mv -f $file.$$.tmp $file || {
      echo >&2 failed removing $mod in $PWD
      exit 1
    }
  done
}

comment_out_in_file()
{
  file=$1 &&
  shift &&
  for mod in "$@"; do
    if grep "^#.*$mod" $file >/dev/null; then
      echo already commented out $mod in $PWD/$file
    else
      echo commenting out $mod in $PWD/$file &&
      filebasename="${file%*.original}" &&
      echo file=$file filebasename=$filebasename &&
      if ! test -f "$filebasename.original"; then
        cp "$file" "$filebasename.original" || {
          echo >&2 failed cp -v $file $filebasename.original in $PWD
          exit 1
        }
      fi &&
      sed -e "s/\(.*$mod.*\)/# rem by install-epics \1/g" <$filebasename.original >$file &&
      ! diff $filebasename.original $file >/dev/null
    fi
  done
}

(
  cd $HOME_EPICS_APPS &&
  if ! test -f baseR${EPICS_BASE_VER}.tar.gz; then
    wget http://www.aps.anl.gov/epics/download/base/baseR${EPICS_BASE_VER}.tar.gz -O baseR${EPICS_BASE_VER}.tar.gz.$$.tmp &&
    mv baseR${EPICS_BASE_VER}.tar.gz.$$.tmp baseR${EPICS_BASE_VER}.tar.gz || {
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
export EPICS_HOST_ARCH
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

#update .epics
cat >${BASH_ALIAS_EPICS} <<EOF
export HOME_EPICS_APPS=$HOME_EPICS_APPS
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
################

(
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
  fi &&
  run_make_in_dir $HOME_EPICS_APPS/base || {
    echo >&2 failed in $PWD
    exit 1
  }
) &&

#Modules
(
  cd $HOME_EPICS_APPS/ &&
  if ! test -d modules; then
    mkdir modules
  fi
) || exit 1



#Streamdevice from PSI
if test -n "$STREAMDEVICEVER"; then
  (
    cd $HOME_EPICS_APPS &&
    if ! test -f $STREAMDEVICEVER.tgz; then
      wget http://epics.web.psi.ch/software/streamdevice/$STREAMDEVICEVER.tgz -O $STREAMDEVICEVER.tgz.$$.tmp &&
      mv $STREAMDEVICEVER.tgz.$$.tmp $STREAMDEVICEVER.tgz || {
        echo >&2 can not wget $STREAMDEVICEVER.tgz
        exit 1
      }
    fi
    if ! test -d $STREAMDEVICEVER; then
      tar xzvf $STREAMDEVICEVER.tgz
    fi
    if ! test -d $HOME_EPICS_APPS/$STREAMDEVICEVER/streamdevice-2.6/configure; then
      mkdir -p $HOME_EPICS_APPS/$STREAMDEVICEVER/streamdevice-2.6/configure
    fi
    (
      # Create the files (Obs: \EOF != EOF)
      cd $HOME_EPICS_APPS/$STREAMDEVICEVER/streamdevice-2.6/configure &&
      cat >CONFIG <<\EOF &&
#Generated by install-epics.sh
# CONFIG - Load build configuration data
#
# Do not make changes to this file!

# Allow user to override where the build rules come from
RULES = $(EPICS_BASE)

# RELEASE files point to other application tops
include $(TOP)/configure/RELEASE
-include $(TOP)/configure/RELEASE.$(EPICS_HOST_ARCH).Common
ifdef T_A
-include $(TOP)/configure/RELEASE.Common.$(T_A)
-include $(TOP)/configure/RELEASE.$(EPICS_HOST_ARCH).$(T_A)
endif
CONFIG = $(RULES)/configure
include $(CONFIG)/CONFIG
# Override the Base definition:
INSTALL_LOCATION = $(TOP)
# CONFIG_SITE files contain other build configuration settings
include $(TOP)/configure/CONFIG_SITE
-include $(TOP)/configure/CONFIG_SITE.$(EPICS_HOST_ARCH).Common
ifdef T_A
 -include $(TOP)/configure/CONFIG_SITE.Common.$(T_A)
 -include $(TOP)/configure/CONFIG_SITE.$(EPICS_HOST_ARCH).$(T_A)
endif
EOF

      cat >CONFIG_SITE <<\EOF &&
#Generated by install-epics.sh
CHECK_RELEASE = YES
EOF

      cat >Makefile <<\EOF &&
#Generated by install-epics.sh
TOP=..
include $(TOP)/configure/CONFIG
TARGETS = $(CONFIG_TARGETS)
CONFIGS += $(subst ../,,$(wildcard $(CONFIG_INSTALLS)))
include $(TOP)/configure/RULES
EOF

      cat >RELEASE <<\EOF &&
#Generated by install-epics.sh
TEMPLATE_TOP=$(EPICS_BASE)/templates/makeBaseApp/top
ASYN=${EPICS_ROOT}/modules/asyn
EPICS_BASE=${EPICS_ROOT}/base
EOF

      cat >RULES <<\EOF &&
#Generated by install-epics.sh
# RULES
include $(CONFIG)/RULES
# Library should be rebuilt because LIBOBJS may have changed.
$(LIBNAME): ../Makefile
EOF

      cat >RULES.ioc <<\EOF &&
#Generated by install-epics.sh
#RULES.ioc
include $(CONFIG)/RULES.ioc
EOF

      cat >RULES_DIRS <<\EOF &&
#Generated by install-epics.sh
#RULES_DIRS
include $(CONFIG)/RULES_DIRS
EOF

      cat >RULES_DIRS <<\EOF
#Generated by install-epics.sh
#RULES_TOP
include $(CONFIG)/RULES_TOP
EOF
    )
  )
fi


if test -n "$ASYNVER"; then
(
  install_asyn_ver ../$ASYNVER &&
    (
      cd $HOME_EPICS_APPS &&
      if ! test -f $ASYNVER.tar.gz; then
        wget http://www.aps.anl.gov/epics/download/modules/$ASYNVER.tar.gz -O $ASYNVER.tar.gz.$$.tmp &&
        mv $ASYNVER.tar.gz.$$.tmp $ASYNVER.tar.gz || {
          echo >&2 can not wget $ASYNVER.tar.gz
          exit 1
        }
      fi
      if ! test -d $ASYNVER; then
        tar xzvf $ASYNVER.tar.gz
      fi
    ) &&
    (
      # Need to fix epics base for synapss already here,
      # (if the dir already exists)
      path=$HOME_EPICS_APPS/$SYNAPPSVER/support/configure &&
      if test -d $path; then
        echo cd $path &&
        cd $path &&
        (
          fix_epics_base EPICS_BASE.$EPICS_HOST_ARCH &&
          fix_epics_base SUPPORT.$EPICS_HOST_ARCH
        )
      fi
    ) &&
    (
      cd $HOME_EPICS_APPS/$ASYNVER/configure && {
        for f in $(find . -name "RELEASE*" ); do
          echo f=$f
          fix_epics_base $f
        done
      }
    ) &&
    (
      run_make_in_dir $HOME_EPICS_APPS/$ASYNVER
    ) || {
      echo >&2 failed $ASYNVER
      exit 1
    }
)
else
  echo ASYNVER not defined, skipping asyn
  install_asyn_ver ../$SYNAPPSVER/support/asyn-4-18
fi

#synApps
if test -n "$SYNAPPSVER"; then
  (
    cd $HOME_EPICS_APPS &&
    if ! test -f $SYNAPPSVER.tar.gz; then
      wget http://www.aps.anl.gov/bcda/synApps/tar/$SYNAPPSVER.tar.gz -O $SYNAPPSVER.tar.gz.$$.tmp &&
      mv $SYNAPPSVER.tar.gz.$$.tmp $SYNAPPSVER.tar.gz || {
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
    if test -n "$STREAMDEVICEVER"; then
      cd $HOME_EPICS_APPS/$SYNAPPSVER/support/stream* &&
      (
        #Move the directory out of its way
        if ! test -d streamdevice.original; then
          mv streamdevice streamdevice.original || {
            echo >&2 can not mv streamdevice streamdevice.original PWD=$PWD
            exit 1
          }
          #copy the later streamdevice
          mkdir streamdevice &&
          cp -R ../../../StreamDevice-2-6/ streamdevice/  || {
            echo >&2 cp -R ../../../StreamDevice-2-6/ streamdevice/PWD=$PWD
            exit 1
          }
        fi
      )
    fi
  ) &&
  (
    path=$HOME_EPICS_APPS/$SYNAPPSVER/support &&
    echo cd $path &&
    cd $path &&
    for f in $(find . -name RELEASE); do
      fix_epics_base $f
    done &&
    (
      cd configure &&
      mkdir -p orig || {
      echo >&2 failed mkdir -p orig in $PWD
        exit 1
      }
      for f in EPICS_BASE.cygwin* EPICS_BASE.linux-* EPICS_BASE.win32-* EPICS_BASE.windows-* SUPPORT.cygwin-*  SUPPORT.linux-*  SUPPORT.win32-*  SUPPORT.windows-*; do
        if test -f "$f"; then
          mv -v "$f" $PWD/orig/ || {
            echo >&2 failed mv "$f" orig/ in $PWD
            exit 1
          }
        fi
      done
    ) &&
    (
      echo cd $HOME_EPICS_APPS/$SYNAPPSVER/support/configure &&
      cd $HOME_EPICS_APPS/$SYNAPPSVER/support/configure &&
      if test "$SYNAPPSVER" = synApps_5_6; then
      (
        path=$HOME_EPICS_APPS/$SYNAPPSVER/support
        echo cd $path &&
        cd $path &&
        if ! test -f makereleaseok; then
          make release && touch makereleaseok || {
            echo >&2 failed make release in $PWD
            exit 1
          }
        else
          echo The file $PWD/makereleaseok exist, skipping make release
        fi
      )
      fi &&
      fix_epics_base $PWD/RELEASE &&
      remove_modules_from_RELEASE RELEASE &&
      (
        echo cd $HOME_EPICS_APPS/$SYNAPPSVER/support &&
        cd $HOME_EPICS_APPS/$SYNAPPSVER/support &&
        file=Makefile &&
        if ! test -f $file.original; then
          cp -v $file $file.original || exit 1
        fi &&
        cp $file.original $file &&
        remove_modules_from_Makefile $file
      ) &&
      file=Makefile &&
      (
        # Remove AREA_DETECTOR and IP from RELEASE
        cd $HOME_EPICS_APPS/$SYNAPPSVER/support/xxx-5*/configure &&
        if ! test -f RELEASE.original; then
          cp -v RELEASE RELEASE.original || exit 1
        fi &&
        sed <RELEASE.original >RELEASE.$$.tmp \
          -e "s!^AREA_DETECTOR!#AREA_DETECTOR!" \
          -e "s!^IP=!#IP=!" \
          -e "s!^SNCSEQ!#SNCSEQ!" &&
        mv -fv RELEASE.$$.tmp RELEASE
      ) &&
      (
        # Remove AREA_DETECTOR and IP from dbd
        cd $HOME_EPICS_APPS/$SYNAPPSVER/support/xxx-5*/xxxApp/src &&
        if ! test -f xxxCommonInclude.dbd.original; then
          cp -v xxxCommonInclude.dbd xxxCommonInclude.dbd.original || exit 1
        fi &&
        sed <xxxCommonInclude.dbd.original >xxxCommonInclude.dbd.$$.tmp \
          -e "s!\(include.*ipSupport.dbd\)!#\1!" &&
        mv -fv xxxCommonInclude.dbd.$$.tmp xxxCommonInclude.dbd
      ) &&
      (
        # Remove AREA_DETECTOR related modules from $file
        cd $HOME_EPICS_APPS/$SYNAPPSVER/support/xxx-5*/xxxApp/src &&
        if ! test -f $file.original; then
          cp -v $file $file.original || exit 1
        fi &&
        cp $file.original $file &&
        for mod in ADSupport NDPlugin simDetector netCDF dxp "xxx_Common_LIBS += ip"; do
          echo removing $mod in $PWD/$file &&
          sed -e "s/\(.*$mod.*\)/#XXX Removed by install-epics.sh XXX  \1/g" <$file >$file.$$.tmp &&
          ! diff $file $file.$$.tmp >/dev/null &&
          mv -f $PWD/$file.$$.tmp $PWD/$file ||{
            echo >&2 failed removing $mod in $PWD
            exit 1
          }
        done
      )
    ) || {
      echo >&2 failed in $PWD
      exit 1
    }
  ) || {
    echo >&2 failed RELEASE in $PWD
    exit 1
  }
  if test "$EPICS_EXTENSIONS_TOP_VER"; then
    (
      cd $HOME_EPICS_APPS &&
      if ! test -f $EPICS_EXTENSIONS_TOP_VER.tar.gz; then
        echo installing $EPICS_EXTENSIONS_TOP_VER &&
        wget http://www.aps.anl.gov/epics/download/extensions/$EPICS_EXTENSIONS_TOP_VER.tar.gz -O $EPICS_EXTENSIONS_TOP_VER.tar.gz.$$.tmp &&
        mv $EPICS_EXTENSIONS_TOP_VER.tar.gz.$$.tmp $EPICS_EXTENSIONS_TOP_VER.tar.gz || {
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
      if ! test -f $EPICS_MSI_VER.tar.gz; then
        echo installing $EPICS_MSI_VER &&
        wget http://www.aps.anl.gov/epics/download/extensions/$EPICS_MSI_VER.tar.gz -O $EPICS_MSI_VER.tar.gz.$$.tmp &&
        mv $EPICS_MSI_VER.tar.gz.$$.tmp $EPICS_MSI_VER.tar.gz || {
          echo >&2 can not wget $EPICS_MSI_VER.tar.gz
          exit 1
        }
      fi &&
      (
        mkdir -p extensions/src &&
        cd extensions/src &&
        tar xzf ../../$EPICS_MSI_VER.tar.gz &&
        cd $EPICS_MSI_VER &&
        run_make_in_dir . || {
          echo >&2 make failed in $PWD
          exit 1
        }
      ) || {
        echo >&2 msi failed in $PWD
        exit 1
      }
    )
  fi &&
  if test -z "$ASYNVER"; then
    #Need to compile asyn from synapps
    run_make_in_dir $HOME_EPICS_APPS/$SYNAPPSVER/support/asyn-*/asyn
  fi &&
  run_make_in_dir $HOME_EPICS_APPS/$SYNAPPSVER/support/sscan* &&
  run_make_in_dir $HOME_EPICS_APPS/$SYNAPPSVER/support/calc-* &&
  run_make_in_dir $HOME_EPICS_APPS/$SYNAPPSVER/support/stream-* || {
    echo >&2 failed $SYNAPPSVER PWD=$PWD PATH=$PATH
    exit 1
  }
  patch_motor_h $HOME_EPICS_APPS/$SYNAPPSVER/support/motor-*/motorApp/MotorSrc &&
  comment_out_in_file $HOME_EPICS_APPS/$SYNAPPSVER/support/motor-*/motorApp/Makefile HytecSrc &&
  run_make_in_dir $HOME_EPICS_APPS/$SYNAPPSVER/support/motor-*/motorApp || {
    echo >&2 failed $SYNAPPSVER PWD=$PWD PATH=$PATH
    exit 1
  }
  install_motor &&
  install_streamdevice &&
  echo install motor streamdevice OK || {
    echo >&2 failed install_streamdevice PWD=$PWD
    exit 1
  }
else
  echo SYNAPPSVER not defined, skipping synApps
fi

