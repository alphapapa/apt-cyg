#!/bin/bash
# apt-cyg: install tool for Cygwin similar to debian apt-get
#
# The MIT License (MIT)
#
# Copyright (c) 2013 Trans-code Design
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

usage="\
NAME
  Sage - package manager utility

SYNOPSIS
  sage [operation] [options] [targets]

DESCRIPTION
  Sage is a package management utility that tracks installed packages on a
  Cygwin system. Invoking Sage involves specifying an operation with any
  potential options and targets to operate on. A target is usually a package
  name, file name, URL, or a search string. Targets can be provided as command
  line arguments.

OPERATIONS
  install
    Install package(s).

  remove
    Remove package(s) from the system.

  update
    Download a fresh copy of the master package list (setup.ini) from the
    server defined in setup.rc.

  download
    Retrieve package(s) from the server, but do not install/upgrade anything.

  show
    Display information on given package(s).

  depends
    Produce a dependency tree for a package.

  rdepends
    Produce a tree of packages that depend on the named package.

  list
    Search each locally-installed package for names that match regexp. If no
    package names are provided in the command line, all installed packages will
    be queried.

  listall
    This will search each package in the master package list (setup.ini) for
    names that match regexp.

  category
    Display all packages that are members of a named category.

  listfiles
    List all files owned by a given package. Multiple packages can be specified
    on the command line.

  search
    Search for downloaded packages that own the specified file(s). The path can
    be relative or absolute, and one or more files can be specified.

  searchall
    Search cygwin.com to retrieve file information about packages. The provided
    target is considered to be a filename and searchall will return the
    package(s) which contain this file.

  mirror
    Set the mirror; a full URL to a location where the database, packages, and
    signatures for this repository can be found. If no URL is provided, display
    current mirror.

  cache
    Set the package cache directory. If a file is not found in cache directory,
    it will be downloaded. Unix and Windows forms are accepted, as well as
    absolute or regular paths. If no directory is provided, display current
    cache.

OPTIONS
  --upgrade
    Install even if already installed. this is useful if you have run
    'sage update' and would like to install the new version.

  --nodeps
    Specify this option to skip all dependency checks.

  --version
    Display version and exit.
"

wget() {
  if command wget -h 2>&1 >/dev/null
  then
    command wget "$@"
  else
    warn wget is not installed, using lynx as fallback
    set "${*: -1}"
    lynx -source "$1" > "${1##*/}"
  fi
}

find_workspace() {
  # default working directory and mirror

  # work wherever setup worked last, if possible
  cache=$(awk '
  BEGIN {
    RS = "\n\\<"
    FS = "\n\t"
  }
  $1 == "last-cache" {
    print $2
  }
  ' /etc/setup/setup.rc)

  mirror=$(awk '
  /last-mirror/ {
    getline
    print $1
  }
  ' /etc/setup/setup.rc)
  mirrordir=$(echo "$mirror" | sed 's./.%2f.g; s.:.%3a.g')

  mkdir -p "$cache/$mirrordir/$arch"
  cd "$cache/$mirrordir/$arch"
  if [ -e setup.ini ]
  then
    return 0
  else
    get_setup
    return 1
  fi
}

get_setup() {
  touch setup.ini
  mv setup.ini setup.ini-save
  wget -N $mirror/$arch/setup.bz2
  if [ -e setup.bz2 ]
  then
    bunzip2 setup.bz2
    mv setup setup.ini
    echo Updated setup.ini
  else
    echo Error updating setup.ini, reverting
    mv setup.ini-save setup.ini
  fi
}

check_packages() {
  if [ "$pks" ]
  then
    return 0
  else
    echo No packages found.
    return 1
  fi
}

warn() {
  printf '\e[1;31m%s\e[m\n' "$*" >&2
}

_update() {
  if find_workspace
  then
    get_setup
  fi
}

_category() {
  check_packages
  find_workspace
  for pkg in "${pks[@]}"
  do
    awk '
    $1 == "@" {
      pck = $2
    }
    $1 == "category:" && $0 ~ query {
      print pck
    }
    ' query="$pks" setup.ini
  done
}

_list() {
  local sbq
  for pkg in "${pks[@]}"
  do
    if [ "$sbq" ]
    then
      echo
    else
      sbq=1
    fi
    awk 'NR>1 && $1~pkg && $0=$1' pkg="$pkg" /etc/setup/installed.db
  done
  if [ "$sbq" ]
  then
    return
  fi
  awk 'NR>1 && $0=$1' /etc/setup/installed.db
}

_listall() {
  check_packages
  find_workspace
  local sbq
  for pkg in "${pks[@]}"
  do
    if [ "$sbq" ]
    then
      echo
    else
      sbq=1
    fi
    awk '$1~pkg && $0=$1' RS='\n\n@ ' FS='\n' pkg="$pkg" setup.ini
  done
}

_listfiles() {
  check_packages
  find_workspace
  local pkg sbq
  for pkg in "${pks[@]}"
  do
    if [ "$sbq" ]
    then
      echo
    else
      sbq=1
    fi
    if [ ! -e /etc/setup/"$pkg".lst.gz ]
    then
      download "$pkg"
    fi
    gzip -cd /etc/setup/"$pkg".lst.gz
  done
}

_show() {
  find_workspace
  check_packages
  local sbq
  for pkg in "${pks[@]}"
  do
    if [ "$sbq" ]
    then
      echo
    else
      sbq=1
    fi
    awk '
    $1 == query {
      print
      fd++
    }
    END {
      if (! fd)
        print "Unable to locate package " query
    }
    ' RS='\n\n@ ' FS='\n' query="$pkg" setup.ini
  done
}

_depends() {
  find_workspace
  check_packages
  for pkg in "${pks[@]}"
  do
    awk '
    @include "join"
    $1 == "@" {
      apg = $2
    }
    $1 == "requires:" {
      for (z=2; z<=NF; z++)
        reqs[apg][z-1] = $z
    }
    END {
      prpg(ENVIRON["pkg"])
    }
    function smartmatch(small, large,    values) {
      for (each in large)
        values[large[each]]
      return small in values
    }
    function prpg(fpg) {
      if (smartmatch(fpg, spath)) return
      spath[length(spath)+1] = fpg
      print join(spath, 1, length(spath), " > ")
      if (isarray(reqs[fpg]))
        for (each in reqs[fpg])
          prpg(reqs[fpg][each])
      delete spath[length(spath)]
    }
    ' setup.ini
  done
}

_rdepends() {
  find_workspace
  for pkg in "${pks[@]}"
  do
    awk '
    @include "join"
    $1 == "@" {
      apg = $2
    }
    $1 == "requires:" {
      for (z=2; z<=NF; z++)
        reqs[$z][length(reqs[$z])+1] = apg
    }
    END {
      prpg(ENVIRON["pkg"])
    }
    function smartmatch(small, large,    values) {
      for (each in large)
        values[large[each]]
      return small in values
    }
    function prpg(fpg) {
      if (smartmatch(fpg, spath)) return
      spath[length(spath)+1] = fpg
      print join(spath, 1, length(spath), " < ")
      if (isarray(reqs[fpg]))
        for (each in reqs[fpg])
          prpg(reqs[fpg][each])
      delete spath[length(spath)]
    }
    ' setup.ini
  done
}

_download() {
  check_packages
  find_workspace
  local pkg sbq
  for pkg in "${pks[@]}"
  do
    if [ "$sbq" ]
    then
      echo
    else
      sbq=1
    fi
    download "$pkg"
  done
}

download() {
  local pkg digest digactual
  pkg=$1
  # look for package and save desc file

  awk '$1 == pc' RS='\n\n@ ' FS='\n' pc=$pkg setup.ini > desc
  if [ ! -s desc ]
  then
    echo Unable to locate package $pkg
    exit 1
  fi

  # download and unpack the bz2 or xz file

  # pick the latest version, which comes first
  set -- $(awk '$1 == "install:"' desc)
  if [ $# = 0 ]
  then
    echo 'Could not find "install" in package description: obsolete package?'
    exit 1
  fi

  dn=$(dirname $2)
  bn=$(basename $2)

  # check the md5
  digest=$4
  case ${#digest} in
   32) hash=md5sum    ;;
  128) hash=sha512sum ;;
  esac
  mkdir -p "$cache/$mirrordir/$dn"
  cd "$cache/$mirrordir/$dn"
  if ! test -e $bn || ! echo "$digest $bn" | $hash -c
  then
    wget -O $bn $mirror/$dn/$bn
    echo "$digest $bn" | $hash -c || exit
  fi

  tar tf $bn | gzip > /etc/setup/"$pkg".lst.gz
  cd "$OLDPWD"
  mv desc "$cache/$mirrordir/$dn"
  echo $dn $bn > /tmp/dwn
}

_search() {
  check_packages
  echo Searching downloaded packages...
  for pkg in "${pks[@]}"
  do
    for manifest in /etc/setup/*.lst.gz
    do
      if gzip -cd $manifest | grep -q "$pkg"
      then
        package=$(echo "$manifest" | sed 's,/etc/setup/,,; s,.lst.gz,,')
        echo $package
      fi
    done
  done
}

_searchall() {
  rsc=$(awk '
  BEGIN {
    printf "cygwin.com/cgi-bin2/package-grep.cgi?text=1&arch=%s&grep=%s",
    ARGV[1], ARGV[2]
  }
  ' $arch $pks)
  wget -O /tmp/matches "$rsc"
  awk '
  NR == 1 {next}
  mc[$1]++ {next}
  /-debuginfo-/ {next}
  /^cygwin32-/ {next}
  {print $1}
  ' FS=-[[:digit:]] /tmp/matches
}

_install() {
  check_packages
  find_workspace
  local pkg dn bn requires wr package sbq script
  for pkg in "${pks[@]}"
  do

  if [ ! -v upgrade ]
  then
    if grep -q "^$pkg " /etc/setup/installed.db
    then
      echo Package $pkg is already installed, skipping
      continue
    fi
  fi
  if [ "$sbq" ]
  then
    echo
  else
    sbq=1
  fi
  echo Installing $pkg

  download $pkg
  read dn bn </tmp/dwn
  echo Unpacking...

  cd "$cache/$mirrordir/$dn"
  tar -x -C / -f $bn
  # update the package database

  awk '
  ins != 1 && pkg < $1 {
    print pkg, bz, 0
    ins = 1
  }
  1
  END {
    if (ins != 1) print pkg, bz, 0
  }
  ' pkg="$pkg" bz=$bn /etc/setup/installed.db > /tmp/awk.$$
  mv /etc/setup/installed.db /etc/setup/installed.db-save
  mv /tmp/awk.$$ /etc/setup/installed.db

  if [ "$nodeps" ]
  then
    continue
  fi
  # recursively install required packages

  requires=$(awk '$1=="requires", $0=$2' FS=': ' desc)
  cd "$OLDPWD"
  wr=0
  if [ "$requires" ]
  then
    echo Package $pkg requires the following packages, installing:
    echo $requires
    for package in $requires
    do
      if grep -q "^$package " /etc/setup/installed.db
      then
        echo Package $package is already installed, skipping
        continue
      fi
      sage install --noscripts $package || wr=1
    done
  fi
  if [ wr = 1 ]
  then
    echo some required packages did not install, continuing
  fi

  # run all postinstall scripts

  if [ "$noscripts" ]
  then
    continue
  fi
  find /etc/postinstall -name '*.sh' | while read script
  do
    echo Running $script
    $script
    mv $script $script.done
  done
  echo Package $pkg installed

  done
}

_remove() {
  check_packages
  cd /etc
  cygcheck awk bash bunzip2 grep gzip mv sed tar xz > setup/essential.lst
  for pkg in "${pks[@]}"
  do

  if ! grep -q "^$pkg " setup/installed.db
  then
    echo Package $pkg is not installed, skipping
    continue
  fi

  if [ ! -e setup/"$pkg".lst.gz ]
  then
    warn Package manifest missing, cannot remove $pkg. Exiting
    exit 1
  fi
  gzip -dk setup/"$pkg".lst.gz
  awk '
  NR == FNR {
    if ($NF) ess[$NF]
    next
  }
  $NF in ess {
    exit 1
  }
  ' FS='[/\\\\]' setup/*.lst
  esn=$?
  if [ $esn = 0 ]
  then
    echo Removing $pkg
    if [ -e preremove/"$pkg".sh ]
    then
      preremove/"$pkg".sh
      rm preremove/"$pkg".sh
    fi
    mapfile dt < setup/"$pkg".lst
    for each in ${dt[*]}
    do
      [ -f /$each ] && rm /$each
    done
    for each in ${dt[*]}
    do
      [ -d /$each ] && rmdir --i /$each
    done
    rm -f setup/"$pkg".lst.gz postinstall/"$pkg".sh.done
    awk -i inplace '$1 != ENVIRON["pkg"]' setup/installed.db
    echo Package $pkg removed
  fi
  rm setup/"$pkg".lst
  if [ $esn = 1 ]
  then
    warn Sage cannot remove package $pkg, exiting
    exit 1
  fi

  done
}

_mirror() {
  if [ "$pks" ]
  then
    awk -i inplace '
    1
    /last-mirror/ {
      getline
      print "\t" pks
    }
    ' pks="$pks" /etc/setup/setup.rc
    echo Mirror set to "$pks".
  else
    awk '
    /last-mirror/ {
      getline
      print $1
    }
    ' /etc/setup/setup.rc
  fi
}

_cache() {
  if [ "$pks" ]
  then
    xr=$(cygpath -aw "$pks")
    ya=$(echo "$xr" | sed 's \\ \\\\ g')
    awk -i inplace '
    1
    /last-cache/ {
      getline
      print "\t" ya
    }
    ' ya="$ya" /etc/setup/setup.rc
    echo "Cache set to '$xr'"
  else
    awk '
    /last-cache/ {
      getline
      print $1
    }
    ' /etc/setup/setup.rc
  fi
}

if [ -p /dev/stdin ]
then
  mapfile -t pks
fi

# process options
until [ $# = 0 ]
do
  case "$1" in

    --nodeps)
      nodeps=1
      shift
    ;;

    --upgrade)
      upgrade=1
      shift
    ;;

    --noscripts)
      noscripts=1
      shift
    ;;

    --version)
      echo 'Sage version 1.1.0'
      exit
    ;;

    update)
      command=$1
      shift
    ;;

    list | cache  | remove | depends | listall  | download | listfiles |\
    show | mirror | search | install | category | rdepends | searchall )
      if [ "$command" ]
      then
        pks+=("$1")
      else
        command=$1
      fi
      shift
    ;;

    *)
      pks+=("$1")
      shift
    ;;

  esac
done

set -a

if [ "$command" ]
then
  readonly arch=$(arch | sed s.i6.x.)
  _"$command"
else
  printf "$usage"
fi
