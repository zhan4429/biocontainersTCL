#! /bin/bash

#  bioc_lua2tcl.sh - Covert biocontainers modulefiles in lua format developed by Purdue University to tcl format.
#  The script will also create bash wrapper each exectuable provided by the application.
#  Usage: bash bioc_lua2tcl.sh - no parameter is required. Need to check directories are correct. 
#
#
# By Yucheng Zhang, Tufts University Research Technology <yzhang85@tufts.edu>, 2023


generate_new_modulefile() {
# generate_new_modulefile "VERSION"
# This is used to convert lua files developed by Purdue University to TCL modulefiles
local app="$1"
local version="$2"
local lua="$3"
local tcl="$4"
local conflict_list=$(grep ^conflict $lua | grep -v myModule | cut -d '(' -f 2 | sed 's/)//g' | sed 's/ //g' | sed 's/\"//g')
local conflict_list=$conflict_list",$app"
IFS=',' read -r -a conflict_array <<< "$conflict_list"
local conflict_uniq_array=( $(printf "%s\n" ${conflict_array[@]} | sort -u) )
local conflicts=$(printf  "%s " "${conflict_uniq_array[@]}")
local conflicts=$(echo $conflicts | xargs echo -n)

cat <<EOF >>$tcl
#%Module -*- tcl -*-
# The MIT License (MIT)
# Copyright (c) 2023 Tufts University

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

EOF
description=$(grep whatis $lua | grep "Description" | cut -d \" -f2)
homepage=$(grep whatis $lua | grep "Home" | cut -d \" -f2)
biocontainers=$(grep whatis $lua |grep "BioContainers" | cut -d \" -f2)
dockerhub=$(grep whatis $lua | grep "Docker"  | cut -d \" -f2)
additional_bind=($(grep SINGULARITY_BIND $lua | cut -d \" -f4))
variables=$(grep pushenv $lua |sed 's/pushenv/setenv/g' | sed 's/(/ /g' |  sed 's/)/ /g' | sed 's/,/ /g')
echo "module-whatis   \"$description\"" >> $tcl
echo "module-whatis   \"$homepage\"" >> $tcl
echo "module-whatis \"Commands: $programs\"" >> $tcl

if [ ! -z "$biocontainers" ]
then
	echo "module-whatis   \"$biocontainers\"" >> $tcl
fi
	
if [ ! -z "$dockerhub" ]
then
	echo "module-whatis   \"$dockerhub\"" >> $tcl
fi


cat <<EOF >>$tcl

set pkg $app 
set ver $ver

proc ModulesHelp { } {
  puts stderr "\tThis module adds $app v$ver to the environment.  It runs as a container under singularity"
}

#
# prepend-path and set SINGULARITY_BIND
#
prepend-path PATH            /cluster/tufts/biocontainers/tools/$app/$ver/bin
prepend-path --delim=, SINGULARITY_BIND /cluster 
EOF


if (( ${#additional_bind[@]} )); then
    printf 'prepend-path --delim=, SINGULARITY_BIND  %s\n' "${additional_bind[@]}"  >> $tcl
fi

cat <<EOF >>$tcl

#
# set environment variable
#
EOF

printf '%s\n' "${variables[@]}"  >> $tcl
grep SINGULARITYENV $lua |cut -d \( -f2  | sed 's/)//g' | sed 's/,/ /g' | awk '//{print "setenv "$0}' >> $tcl

cat <<EOF >>$tcl

#
# list conflict modules that cannot be loaded together
#
set conflicts_modules {$conflicts}
foreach a_conflict \$conflicts_modules {
  conflict \$a_conflict
}

#
# appended log section
# 

if {[module-info mode "load"]} {
  global env
  if {[info exists env(USER)]} {
    set the_user [lindex [array get env USER] 1]
  } else {
    set the_user "foo"
  }
  system [concat "logger environment-modules" [module-info name] \$the_user ]
}

set additional_prereqs {"singularity/3.8.4" "squashfs/4.4"}
if {[module-info mode "load"]} {
  foreach a_module \$additional_prereqs {
    if {![is-loaded \$a_module]} {
      module load \$a_module
    }
  }
}
EOF

}


generate_executable() {
# This is used to convert bash wrappers for commands provided by applications.
local app=$1
local version=$2
local command=$3
local executable=/cluster/tufts/rt/yzhang85/biocontainers/tools/$app/$ver/bin/$command
local lua=$4
local IMAGE=$(grep "local image" $lua | cut -d \" -f 2)        
local ENTRYPOINT_ARGS=$(grep 'local entrypoint_args' $lua | cut -d \" -f 2)
cat <<EOF >>$executable
#!/usr/bin/env bash

if [ ! \$(command -v singularity) ]; then
        module load singularity/3.8.4 squashfs/4.4
fi

VER=$version
PKG=$app
PROGRAM=$command
DIRECTORY=/cluster/tufts/biocontainers/images
IMAGE=$IMAGE
ENTRYPOINT_ARGS="$ENTRYPOINT_ARGS"

## Determine Nvidia GPUs (to pass coresponding flag to Singularity)
if [[ \$(nvidia-smi -L 2>/dev/null) ]]
then
        echo "BIOC: Enabling Nvidia GPU support in the container."
        OPTIONS="--nv"
fi
	
singularity exec \$OPTIONS \$DIRECTORY/\$IMAGE \$ENTRYPOINT_ARGS \$PROGRAM "\$@"
EOF

chmod +x $executable
}


current_dir="$PWD" # save current directory 
cd ../../ # go up two directories
repo_path="$PWD" # assign path to repo_path
lua_dir="$PWD/luas"
tcl_dir="$PWD/tcls"
cd $current_dir # cd back to current directory

for module in $lua_dir/*; do
        app="$(basename $module)";
        version_folder="$module/"
        filenamesarray=`ls $version_folder*.lua`
        tcl_folder="$tcl_dir/$app"
	rm -rf $tcl_folder
        mkdir -p $tcl_folder
        for lua in $filenamesarray
        do
                ver=$(basename -- "$lua" .lua)
                tcl_output="$tcl_dir/$app/$ver"
#               programs=$(grep 'local programs' $lua | cut -d '{' -f 2 |sed 's/}//g'| sed 's/\"//g')
                programs=$(sed -n '/local programs/,/}/p; /}/q' $lua | tr -d "[:space:]"   | cut -d '{' -f 2 |sed 's/}//g' | sed 's/\"//g' |sed 's/\s*$//g' |
 sed 's/,$//')
                generate_new_modulefile $app $ver $lua $tcl_output
                IFS=',' read -r -a program_array <<< "$programs"
                rm -rf /cluster/tufts/rt/yzhang85/biocontainers/tools/$app/$ver/bin
                mkdir -p /cluster/tufts/rt/yzhang85/biocontainers/tools/$app/$ver/bin
                for program in "${program_array[@]}"
                do
                        generate_executable $app $ver $program $lua
                done
        done
done
