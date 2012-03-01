#!/bin/sh

# Copyright 2012, Neil Smithline.

# NBC by Neil Smithline is licensed under a Creative Commons
# Attribution-NonCommercial-ShareAlike 3.0 Unported License. Futher
# information can be found at https://github.com/Neil-Smithline/nbc.

# ####################################################################
# USER SETTINGS
# ####################################################################
# NB_BIN: Should point to the complete path of the `nb' shell script
NB_BIN="$HOME/Desktop/+InstalledCrap/nb/nb"

# DEBUG_LEVEL: Control program verbosity.
# Tracing displays progress information as data is processed.
# Debugging displays internal information as data is processed.
# Between -1 and 19, each value of DEBUG_LEVEL produces more output.
#    -1: Only display error messages.
#     0: Standard value. Only error messages and warnings.
#  1-10: Enable increasing levels of tracing.
# 10-19: Enable increasing levels of debugging.
#    50: Enable bash -x debugging in specific functions
#   100: Enable bash -x debugging throughout script
DEBUG_LEVEL=0
# If DEBUG_LEVEL >= 50 then set -x in DEBUG_FUNCTION_LIST functions.
# The list begins with BEGIN and ends with END. Function names
# are separated by colons. For example, setting -x for func1 is:
#    BEGIN:func1:END
# Setting -x for many funcs is
#    BEGIN:func1:func2:func3:...:funcN:END
# Setting -x for no functions is:
#    BEGIN:END
# or an empty assignment
DEBUG_FUNCTION_LIST="BEGIN:call_NB:check_args_used:END"
# ####################################################################

# ####################################################################
# Get our command name.
# ####################################################################
CMD_NAME=${ORIG_ARG_0##*/}

# ####################################################################
# Set up debugging and error functionality.
# ####################################################################

# Be safe and generate errors if we shift too many times. 
shopt -s shift_verbose

# Set extglob so [ -n "${MYVAR/+([0-9])/}" ] will detect any
# non-digits in MYVAR
shopt -s extglob

if [ "$DEBUG_LEVEL" -ge 50 ]; then
    echo "$cmd_name: >>>> Debugging functions: $DEBUG_FUNCTION_LIST <<<<"
fi

if [ "$DEBUG_LEVEL" -ge 100 ]; then
    set -x
fi

# Print an error and exit. First argument is error number. Remaining
# args are error message.
ERROR () {
    local errno=$1; shift
    echo "$CMD_NAME: Error(${errno}): $@" 1>&2
    exit $errno
}

# Print a debug commmand. First argument is debug level. Remaining
# args are message. Message will only be printed if $ <= $DEBUG_LEVEL 
DEBUG () {
    local level=$1; shift
    if [[ "$level" -le "$DEBUG_LEVEL" ]]; then
        echo "$CMD_NAME: Info($level): $@" 1>&2
    fi
}

# Echo "set -x" or "set +x" based on $1 and DEBUG_FUNCTION_LIST
DEBUGX () {
return
   if [ "$DEBUG_LEVEL" -ge 50 ]; then
        if [ "${DEBUG_FUNCTION_LIST}" = "${DEBUG_FUNCTION_LIST##*:${1}:}" ]; then
            echo "set +x"
        else
            echo "set -x"
        fi
    fi
}

# ####################################################################
# Set up some variables
# ####################################################################
WUP_DISABLED="--no-preview --no-update --no-publish"
WUP_ENABLED=
WUP=unset

# ####################################################################
# Call NB to do its thang!
# ####################################################################
call_NB() {
    $(DEBUGX "call_NB")
    local wup_params=
    case "$WUP" in
        ENABLED)    wup_params="$WUP_ENABLED"   ;;
        DISABLED)   wup_params="$WUP_DISABLED"  ;;
        *)          ERROR -2 "Internal error. \$WUP should not equal '$WUP'" ;;
    esac
    # We have to split up strings such as "tag entry" into separate
    # parameters to NB. To do this we use $* rather than "$*" or
    # other.
    ${NB_BIN} ${wup_params} ${*}
}

# ####################################################################
# Utility functions.
# ####################################################################

# Call this when you are done processing arguments. Pass $# as the
# only argument. It will return or produce an error.
check_args_used () {
    $(DEBUGX "check_args_used")
    if [ "$1" != 0 ]; then
        ERROR -4 "Extra arguments at end of command: '$CMD_NAME'."
    fi
}

create_tag () {
    ${NB_BIN} --title $1 add tag
}

# Take a tag name or number in $1 and print the tag number
get_tag_id () {
    $(DEBUGX "get_tag_id")
    # No quotes on $1 as it should always be an identifier.
    local tag=$1
    local temp=${tag##[0-9]*}
    local id
    
    # If we were passed an integer just return it.
    if [ -z "$temp" ]; then
        id="$tag"
    else
        # Calculate it.
        id=$(${NB_BIN} list tags | egrep "^[ 	]*[0-9]*,[	 ]${tag}$" | sed 's/,.*$//; s/ //g')
    fi
    # Make sure we only have a single number in $id. 
    if [ -n "${id/+([0-9])/}" ]; then
        ERROR -6 "Internal error: '$tag' mapped to illegal tag id: '$id'."
    fi
    echo "$id"
}

# Create a list of tags from parameters.
get_tag_ids () {
    $(DEBUGX "get_tag_ids")
    local t
    local tag_ids=""
    local tags=$(echo "$@" | sed 's/,/ /g')
    local tag_id_separator=""
    for t in $tags; do
        local tid=$(get_tag_id ${t})
        $(DEBUGX "get_tag_ids")
        if [ -z "$tid" ]; then
           create_tag ${t}
           local tid=$(get_tag_id ${t})
           $(DEBUGX "get_tag_ids")
        fi
        tag_ids=${tid}${tag_id_separator}${tag_ids}
        tag_id_separator=","
    done
    echo "$tag_ids"
}

# Process entries.
# $1: NB command arguments
# $2: List of entries.
# Loop through blog entries calling NB with each entry id appended to
# the command
process_entries () {
    local setx=$(DEBUGX "process_entries")
    $setx
    local nb_args="$1"; shift
    local entries=$(echo "$1" | sed 's/,/ /g'); shift
    local e
    for e in ${entries}; do
        DEBUG 1 ">>>> Processing entry $e."
        eval $cmd $e
        $setx
    done
}

# Process entries with tags.
# $1: NB command arguments
# $2: List of tag names.
# $3-n: Entries
# Loop through blog entries calling NB with each entry id appended to
# the command passing the tags with NB's "--tag" argument.
process_entries_with_tags () {
    local setx=$(DEBUGX "process_entries_with_tags")
    $setx
    local cmd_string="$1"; shift
    local tags="$1"; shift
    local entries=$(echo "$@" | sed 's/,/ /g'); shift

    local tag_ids=$(get_tag_ids "$tags")
    $setx
    local e

    WUP="DISABLED"
    for e in ${entries}; do
        DEBUG 1 ">>>> Processing entry $e."
        call_NB --tag "$tag_ids" "$cmd_string" $e
        $setx
    done
}

# ################################################################
# Command NAME TRANSLATION GUIDE
# ################################################################
# 
# The function of a command is encoded in the command's name. In order
# to produce short command names, single-letter abbreviations are used
# in the command name.
#
# NOTE: All commands names are lower-case letters only. Within this
# documentation, upper-case letters are used to emphasize command
# names. When using the comands, simply use the lower-case version of
# any command discussed in this documentation.
#
# All command begin with NB and then have one or more letters
# following them to describe their functionality. For example, looking
# at the table below you can see that the abbreviation for "Publish"
# is "H". As such, the command to publish your blog is "NBH"
#
# ALL ABBREVIATIONS
# cat <<END_OF_TABLE > /dev/null
# |-----------------------------+--------+---------|
# | MEANING                     | ABBREV | TYPE    |
# |-----------------------------+--------+---------|
# | All commands begin with NB. | NB     | Special |
# |-----------------------------+--------+---------|
# | Entry or Entries            | E      | Noun    |
# | ta_G_ or ta_G_s             | G      | Noun    |
# | Template or Templates       | T      | Noun    |
# | Mai_N_                      | N      | Noun    |
# | Max                         | M      | Noun    |
# | E_X_pired                   | X      | Noun    |
# | A_R_ticles                  | R      | Noun    |
# | Feeds                       | F      | Noun    |
# | We_B_log                    | B      | Noun    |
# | We_B_log                    | B      | Noun    |
# |-----------------------------+--------+---------|
# | Update                      | U      | Verb    |
# | Update-_C_ache              | C      | Verb    |
# | Preview_W_                  | W      | Verb    |
# | Delete                      | D      | Verb    |
# | List                        | L      | Verb    |
# | Publis_H_                   | H      | Verb    |
# | Add                         | A      | Verb    |
# |-----------------------------+--------+---------|
# END_OF_TABLE 
#
# Each command has at least one verb (ie: an operation). Publishing
# your blog, NBH, is a command with just a single verb. There are some
# convenience commands that combine multiple operations such as Update
# then Preview. That command is NBUW.
#
# Note that the ordering is significant. NBUW Updates the blog before
# Previewing it. There is no NBWU command. If you wish to Preview your
# blog and then Update it (IMO, a strange thing to want to do), you
# could run NBW followed by NBU.
#
# While operations such as Publishing and Previewing operate on the
# blog as a whole, other commmands operate on specific items of the
# blog. Each item is represented in the command name by its
# appropriate abbreviation.
#
# Excluding the Listing commands, each there is a direct
# correspondence to abbreviations for nouns in the command name and
# the arguments that are to be passed. That is, commands that take
# Entries require that a list of Entries be one of the command-line
# arguments. Likewise, commands take take Tags require that a list of
# Tags be one of the command-line arguments.
#
# Looking at the table above, you can see that the abbreviation for
# Entries is E and the abbreviation for Delete is D. Entries is a noun
# and Delete is a verb. The command to delete one or more entries is
# NBED with command-line arguments that are a list of entries.
#
# While the command to Delete Entries could be NBDE, by convention the
# nouns come before the verbs. This is called postfix syntax, reverse
# Polish notation, or simply RPN. 
#
# There are a few commands such as Tagging Entries that require two
# nouns: a tag list and an entry list. In the command name, the
# subject of the command always comes first. In this case, you are
# adding Tags to the Entries so the Entries are the subject. Hence the
# command is NBEGA. E designates that the subject is Entries. G
# designates that the "secondary parameter" or "direct object" is
# Tags. Finally, A states that the command will Add the secondary
# parameter to the subject.
#
# When passing parameters to the commands, Tags always come before
# Entries. For example, the two parameters that NBEGA takes, Entries
# and Tags, will be passed on the command line with the Tags coming
# before the Entries.
#
# Listing commands (ie: commands where "list" is the verb) are a bit
# different than the other commands. The listing commands require a
# noun such as Entries, but the noun is intepreted as type and not a
# reference to specific entries. As such, the command NBEL takes no
# arguments even though it has a subject of Entries.
#
# As you use the commands, you will become able to automatically know
# the name of the command you wish to execute, the parameters it will
# take, and the order of those parameters. For example, NBED will
# Delete Entries. It takes a list of entries as its parameters. NBEGD
# will Delete Tags from Entries. Its parameters are a list of Tags
# (remember, Tags always come before Entries) and a list of Entries.

# The main processing code.
do_cmd() {
    $(DEBUGX "do_cmd")
    case "$CMD_NAME" in
        nbegd)
            local tags="$1"; shift
            process_entries_with_tags "delete entry" "$tags" "$@"
            ;;

        nbega)
            local tags="$1"; shift
            process_entries_with_tags "tag-entry" "$tags" "$@"
            ;;

        nbga)
            WUP="ENABLED"
            call_NB --title "$@" add tag
            ;;

        nbu)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update all
            ;;

        nbgu)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update tag
            ;;

        nbnu)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update main
            ;;

        nbmu)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update max
            ;;

        nbxu)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update expired
            ;;

        nbl)
            WUP="DISABLED"
            check_args_used $#
            call_NB list all
            ;;

        nbgl)
            WUP="DISABLED"
            check_args_used $#
            call_NB list tags
            ;;

        nbel)
            WUP="DISABLED"
            check_args_used $#
            call_NB list entries
            ;;

        nbml)
            WUP="DISABLED"
            check_args_used $#
            call_NB list max
            ;;

        # nbxl does not exist as you can't call: nb list expired

        nbed)
            WUP="DISABLED"
            process_entries "delete entry" "$@"
            ;;

        nbh)
            WUP="ENABLED"
            check_args_used $#
            call_NB publish
            ;;

        nbw)
            WUP="ENABLED"
            check_args_used $#
            call_NB preview
            ;;

        nbgd)
            tag_ids=$(get_tag_ids "$1"); shift
            check_args_used $#
            ${NB_BIN} delete tag $tag_ids
            ;;
    
        nbuw)
            WUP="ENABLED"
            check_args_used $#
            call_NB -f update all
            call_NB preview
            ;;

        nbc)
            # Call NB directly and pass it all arguments without modification
            ${NB_BIN} "$@"
            ;;

        nbtest)
            # This exists to allow tests of various commands while
            # debugging or enhancing nbc.
            get_tag_ids ${*}
            ;;

        nbdebug)
            # Provide debugging support by doing nothing.
            # This allows you to do: $ nbdebug
            # at your bash prompt and turn your bash into an
            # interactive version of nbc where you can call functions
            # and examine variables
            ;;

        *)
            ERROR -3 "Do not know how to process command $CMD_NAME."
            ;;
    esac
}

do_cmd "$@"