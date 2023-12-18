#! /bin/bash

#  bioc_lua2tcl.sh - Covert biocontainers modulefiles in lua format developed by Purdue University to tcl format.
#  The script will also create bash wrapper each exectuable provided by the application.
#  Usage: bash bioc_lua2tcl.sh -i Lua_dir -o tcl_output. 
#
#
# By Yucheng Zhang, Tufts University Research Technology <yzhang85@tufts.edu>, 2023

# Define options and default values
input_dir=""
output_dir=""

# Define functions
# ----------------------------------------------------------------------
# Function to display usage information
# ----------------------------------------------------------------------
print_usage() {
  echo "Usage: $0 [--help/-h] [--input/-i INPUT_DIR] [--output/-o OUTPUT_DIR]"
  echo "  -h, --help     Display help message and exit."
  echo "  -i, --input    Path to the input directory containing lua files."
  echo "  -o, --output  Path to the output directory (default: tcls)."
  exit 1
}

# ----------------------------------------------------------------------
# Function generate_new_modulefile definition
# ----------------------------------------------------------------------

generate_new_modulefile() {
    # generate_new_modulefile $APP $VERSION $LUA $TCLout
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
    echo "module-whatis \"Commands: $PROGRAMS\"" >> $tcl

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
set ver $version

proc ModulesHelp { } {
  puts stderr "\tThis module adds $app v$version to the environment.  It runs as a container under singularity"
}

#
# prepend-path and set SINGULARITY_BIND
#
prepend-path PATH            $AppTool_dir
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

set additional_prereqs {"singularity"}
if {[module-info mode "load"]} {
  foreach a_module \$additional_prereqs {
    if {![is-loaded \$a_module]} {
      module load \$a_module
    }
  }
}
EOF

}


# ----------------------------------------------------------------------
# Function generate_executable definition
# ----------------------------------------------------------------------

generate_executable() {
      # This is used to convert bash wrappers for commands provided by applications.
      # generate_executable $APP $VERSION $PROGRAM $LUA
      local app=$1
      local version=$2
      local command=$3
      local executable=$AppTool_dir/$command
      local lua=$4
      local IMAGE=$(grep "local image" $lua | cut -d \" -f 2)        
      local ENTRYPOINT_ARGS=$(grep 'local entrypoint_args' $lua | cut -d \" -f 2)
echo $executable
cat <<EOF >>$executable
#!/usr/bin/env bash

if [ ! \$(command -v singularity) ]; then
        module load singularity
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
        OPTIONS="--nv"
fi
	
singularity exec \$OPTIONS \$DIRECTORY/\$IMAGE \$ENTRYPOINT_ARGS \$PROGRAM "\$@"
EOF

      chmod +x $executable
}

# ----------------------------------------------------------------------
# Main logic
# ----------------------------------------------------------------------
# Parse options
while getopts ":hi:o:" opt; do
  case $opt in
    h)
      print_usage
      ;;
    i)
      input_dir="$OPTARG"
      ;;
    o)
      output_dir="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      print_usage
      ;;
  esac
done

# Check for required options and validate input
if [[ -z "$input_dir" ]]; then
  echo "Error: Missing the input directory containing lua files" >&2
  print_usage
fi

TCLmodules_dir=$output_dir/tcls
TCLtools_dir=$output_dir/tools

## Create output folders if not exsit
if [[ ! -d "$TCLmodules_dir" ]]; then
  mkdir -p "$TCLmodules_dir"
  echo "Old folder '$TCLmodules_dir' created successfully."
else
  echo "Old folder '$TCLmodules_dir' already exists."
fi

if [[ ! -d "$TCLtools_dir" ]]; then
  mkdir -p "$TCLtools_dir"
  echo "Old folder '$TCLtools_dir' created successfully."
else
  echo "Old folder '$TCLtools_dir' already exists."
fi

for APP in $input_dir/*; do
        APP="$(basename $APP)";
        VersionArray=$(ls $input_dir/$APP/*.lua)
        TCL_dir="$TCLmodules_dir/$APP"
        # Check if the folder exists
        if [[ -d "$TCL_dir" ]]; then
            rm -rf "$TCL_dir"
            echo "Old folder '$TCL_dir' removed successfully."
        fi
        mkdir -p $TCL_dir
        for LUA in $VersionArray
        do
            VERSION=$(basename -- "$LUA" .lua)
            TCLout="$TCL_dir/$VERSION"
            PROGRAMS=$(sed -n '/local programs/,/}/p; /}/q' $LUA | tr -d "[:space:]"   | cut -d '{' -f 2 |sed 's/}//g' | sed 's/\"//g' |sed 's/\s*$//g' | sed 's/,$//')
            ## Generate modulefiles
            generate_new_modulefile $APP $VERSION $LUA $TCLout
            ## Generate bash wrappers for exectuables
            IFS=',' read -r -a PROGRAMarray <<< "$PROGRAMS"
            # Check if the folder exists
            AppTool_dir=$TCLtools_dir/$APP/$VERSION/bin
            if [[ -d "$AppTool_dir" ]]; then
                rm -rf "$AppTool_dir"
                echo "Old folder '$AppTool_dir' removed successfully."
            fi
            mkdir -p $AppTool_dir
            for PROGRAM in "${PROGRAMarray[@]}"
            do
                  generate_executable $APP $VERSION $PROGRAM $LUA
            done
        done
done
