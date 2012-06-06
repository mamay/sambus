#!/bin/bash

# Samba preExec script
# Version 0.2
# 
# Combines user's and groups' shares and make one applied by user
# smb.conf, containing all the allowed shares
# Optimized by checking mtimes of all the applied configs
# Written LAZY algorithms
#
# Version 0.2 ChangeLog
# Added some portions of code to get much more debug info on users, etc
# Implemented error codes
# Patched some errors
#
# (c) by Yuri Mamaev aka MaSTeR_MaMay at 06/06/2012
#
# License pending
#

log_file=/var/log/samba/preexec.log
conf=/etc/samba/conf
debug=5
groups_cache_expire=600 # seconds

#### Error codes definitions ####
E_OK=0
E_ERROR=1
E_WARNING=15
E_CRITICAL=16
E_FILE_NOT_FOUND=2
E_CHECK_NOT_FOUND=3
E_FILE_NOT_WRITABLE=4
#################################

#### Log codes definitions ####
LOG_OK=0
LOG_NORMAL=0
LOG_ERROR=1
LOG_WARNING=2
LOG_INFO=3
LOG_VERBOSE=4
LOG_DEBUG=5
###############################


is_groups_loaded=0
is_shares_loaded=0
is_user_exists=16

load_date()
{
        echo `date "+%d.%m.%y %H:%M:%S -- "`
}

return_code()
{
	case $1 in
		${E_OK})
			echo E_OK
			;;
		${E_ERROR})
			echo E_ERROR
			;;
		${E_WARNING})
			echo E_WARNING
			;;
		${E_CRITICAL})
			echo E_CRITICAL
			;;
		${E_FILE_NOT_FOUND})
			echo E_FILE_NOT_FOUND
			;;
		${E_CHECK_NOT_FOUND})
			echo E_CHECK_NOT_FOUND
			;;
		${E_FILE_NOT_WRITABLE})
			echo E_FILE_NOT_WRITABLE
			;;
		*)
			echo E_ERROR
			;;
	esac
}

log_code()
{
	case $1 in

                ${LOG_OK})
                        echo ""
                        ;;
                ${LOG_ERROR})
                        echo "Error: "
                        ;;
                ${LOG_WARNING})
                        echo "Warning: "
                        ;;
                ${LOG_INFO})
                        echo "Info: "
                        ;;
                ${LOG_VERBOSE})
                        echo "Verbose: "
                        ;;
                ${LOG_DEBUG})
                        echo "Debug: "
                        ;;
                *)
                        echo "Unknown: "
                        ;;
        esac
}

do_log()
{

	local dbg=$1
	local retval=$2
	shift 2
	
	if [ ${dbg} -le ${debug} ]; then
		echo -e $(load_date) $(log_code ${dbg}) $@ "($(return_code ${retval}))" >> ${log_file}
	fi
	
}

load_vars()
{
	local OPTIND
	while getopts :u:d:i:m: opt; do
		case $opt in
			u)
				user=$OPTARG
				;;
			d)
				domain=$OPTARG
				;;
			i)
				ip=$OPTARG
				;;
			m)
				machine=$OPTARG
				;;
			\?)
				do_log 2 "Invalid option: -$OPTARG"
				;;
		esac
	done
	return ${E_OK}
}

user_exists()
{
	if [ -z "${user}" ]; then
		do_log ${LOG_VERBOSE} ${E_ERROR} "User string empty."
		return ${E_ERROR}
	fi
	if [ ${is_user_exists} -eq 16 ]; then
		user_content=`id "${user}"`
		is_user_exists=$?
	fi
	do_log ${LOG_VERBOSE} ${E_OK} "Is user exists: ${is_user_exists}"
	return ${is_user_exists}
}

is_writable()
{
	touch "$1"
	return $?
}

load_groups()
{
	if [ ${is_groups_loaded} -eq 1 ]; then
		do_log ${LOG_DEBUG} ${E_OK} "Groups already loaded! (${is_groups_loaded})"
		return ${E_OK}
	fi
	user_exists ${user}
	local ret=$?
	do_log ${LOG_DEBUG} ${E_OK} "Load groups: user exists: ${ret}"
	if ( user_exists ); then
		groups_all=`echo "${user_content}" | egrep -o 'groups=.*' | sed -e 's/groups=//' -e 's/)//g' -e 's/[0-9]*(//g'`
		do_log ${LOG_DEBUG} ${E_OK} "Groups all: ${groups_all}"
		IFS=$","
		local i=0
		for group in ${groups_all}
		do
			groups[${i}]="${group}"
			let "i+=1"
		done
		unset IFS
		is_groups_loaded=1
		return ${E_OK}
	else
		do_log ${LOG_ERROR} ${E_CRITICAL} "Load groups failed, user_exists returned 1"
		return ${E_CRITICAL}
	fi
}

check_groups()
{
        if [ -e ${conf}/${domain}/md5sums/u_${user} ]; then
                echo "${groups_all}" | md5sum --check --status ${conf}/${domain}/md5sums/u_${user}
		local ret=$?
		do_log ${LOG_VERBOSE} ${ret} "Group list MD5 checksum returned ${ret}"
                return ${ret}
        else
		do_log ${LOG_DEBUG} ${E_FILE_NOT_FOUND} "User group list md5sum does not exist!"
                return ${E_FILE_NOT_FOUND}
        fi
}

write_groups()
{
	if ( is_writable "${conf}/${domain}/md5sums/${user}" ); then
	        echo "${groups_all}" | md5sum - > "${conf}/${domain}/md5sums/u_${user}"
		do_log ${LOG_DEBUG} ${E_OK} "Written user ${user} groups list md5sum"
	        return ${E_OK}
	else
		do_log ${LOG_ERROR} ${E_FILE_NOT_WRITABLE} "Cannot write user ${user} groups list md5sum"
		return ${E_FILE_NOT_WRITABLE}
	fi
	
}

load_shares()
{
        local e_count
        local i=0
	local group_shares
	local user_shares
	local share
        e_count=${#groups[@]}

        while [ "$i" -lt "$e_count" ]
        do
		if [ -e "${conf}/${domain}/groups/${groups[$i]}" ]; then
			group_shares=`cat "${conf}/${domain}/groups/${groups[$i]}"`
			shares_all=`echo -e "${shares_all}\n$group_shares"`
		fi
                let "i+=1"
        done
	if [ -e "${conf}/${domain}/users/${user}" ]; then
		user_shares=`cat "${conf}/${domain}/users/${user}"`
	        shares_all=`echo -e "${shares_all}\n$user_shares"`
	fi

	# Clean the shares list from empty lines, sort and make unique list
	shares_all=`echo "${shares_all}" | sed '/^$/d' | sort -u`
	do_log ${LOG_VERBOSE} ${E_OK} "Loaded shares list user (${user}): ${shares_all}"
	i=0
	for share in ${shares_all}
	do
		if [ -n "${share}" ]; then
			shares[${i}]="${share}"
		fi
		let "i+=1"
	done
	is_shares_loaded=1
        return ${E_OK}
}

get_mtime()
{
	if [ -e "$1" ]; then
		echo $(stat -c "%Y" "$1")
		return ${E_OK}
	else
		return ${E_FILE_NOT_FOUND}
	fi
}

load_mtime()
{
	local type=$1
        local name=$2
	local object=$3

	if [ -e "${conf}/${domain}/mtimes/${type}_${name}" ]; then
		local mtime=`cat "${conf}/${domain}/mtimes/${type}_${name}"`
		if [ -n "${mtime}" ] && [ ${mtime} -gt 1 ]; then
			echo "${mtime}"
			return ${E_OK}
		else
			return ${E_ERROR}
		fi
	else
		return ${E_FILE_NOT_FOUND}
	fi
}

check_mtime()
{
	local type=$1
        local name=$2
	local object

        case ${type} in
                g)
                        object="group"
			type="g_${user}"
                        ;;
                u)
                        object="user"
                        ;;
                s)
                        object="share"
                        type="s_${user}"
                        ;;
                *)
                        return 4
                        ;;
        esac

	local gmtime
	local smtime
	
	gmtime=`get_mtime "${conf}/${domain}/${object}s/${name}"`
	local ret=$?

	if [ ${ret} -eq ${E_OK} ]; then
		smtime=`load_mtime "${type}" "${name}" "${object}"`
		ret=$?

		if [ ${ret} -eq ${E_OK} ]; then

			do_log ${LOG_DEBUG} ${E_OK} "(${object}s/${name}) mtime: ${gmtime}, (mtimes/${type}_${name}): ${smtime}"
			if [ ${gmtime} -eq ${smtime} ]; then
				return ${E_OK}
			else
				return ${E_ERROR}
			fi

		elif [ ${ret} -eq ${E_FILE_NOT_FOUND} ]; then
			return ${E_CHECK_NOT_FOUND}
		else
			return ${E_ERROR}
		fi
	elif [ -e "${conf}/${domain}/mtimes/${type}_${name}" ]; then
		rm "${conf}/${domain}/mtimes/${type}_${name}"
		return ${E_ERROR}
	else
		return ${E_FILE_NOT_FOUND}
	fi
}

config_exists()
{
	if [ -e "${conf}/${domain}/applied/${user}" ]; then
		do_log ${LOG_DEBUG} ${E_OK}  "${user} config exists"
		return ${E_OK}
	else
		do_log ${LOG_VERBOSE} ${E_FILE_NOT_FOUND} "${user} config does not exist"
		return ${E_ERROR}
	fi
}

save_mtime()
{
	local type=$1
        local name=$2
	local object

	case ${type} in

                g)
                        object="group"
			type="g_${user}"
                        ;;
                u)
                        object="user"
                        ;;
                s)
                        object="share"
			type="s_${user}"
                        ;;
                *)
                        return 4
                        ;;
        esac

	if [ ! -e "${conf}/${domain}/${object}s/${name}" ]; then
		return ${E_FILE_NOT_FOUND}
	fi

	if ( is_writable "${conf}/${domain}/mtimes/${type}_${name}" ); then
		get_mtime "${conf}/${domain}/${object}s/${name}" > "${conf}/${domain}/mtimes/${type}_${name}"
		return $?
	else
		do_log ${LOG_DEBUG} ${E_FILE_NOT_WRITABLE} "Cannot write ${conf}/${domain}/mtimes/${type}_${name}"
		return ${E_FILE_NOT_WRITABLE}
	fi
}


check_groups_mtimes()
{
        local e_count
        local i=0
	local ret=0
        e_count=${#groups[@]}

        while [ "$i" -lt "$e_count" ]
        do
		check_mtime "g" "${groups[$i]}"
		ret=$?
		if [ ${ret} -eq ${E_ERROR} ] || [ ${ret} -eq ${E_CHECK_NOT_FOUND} ]; then
			do_log ${LOG_VERBOSE} ${E_OK} "User's ${user}: group (${groups[$i]}) mtime not OK (${ret})"
			return ${E_ERROR}
		fi
                let "i+=1"
        done
	return ${E_OK}
}

check_shares_mtimes()
{
        local e_count
        local i=0
	local ret=0
        e_count=${#shares[@]}

        while [ "$i" -lt "$e_count" ]
        do
		check_mtime "s" "${shares[$i]}"
		ret=$?
                if [ ${ret} -eq ${E_ERROR} ] || [ ${ret} -eq ${E_CHECK_NOT_FOUND} ]; then
                        do_log ${LOG_VERBOSE} ${E_OK} "User's ${user}: share (${shares[$i]}) mtime not OK (${ret})"
                        return ${E_ERROR}
                fi
                let "i+=1"
        done
        return ${E_OK}
}

save_shares_mtimes()
{
        local e_count
        local i=0
	local ret=0
        e_count=${#shares[@]}

        while [ "$i" -lt "$e_count" ]
        do
		check_mtime "s" "${shares[$i]}"
		ret=$?
                if [ ${ret} -eq ${E_ERROR} ] || [ ${ret} -eq ${E_CHECK_NOT_FOUND} ]; then
			save_mtime "s" "${shares[$i]}"
			ret=$?
                        do_log ${LOG_VERBOSE} ${ret} "User's \"${user}\": share \"${shares[$i]}\" saving NEW mtime (${ret})"
                fi
                let "i+=1"
        done
        return ${E_OK}
}

save_groups_mtimes()
{
        local e_count
        local i=0
	local ret=0
        e_count=${#groups[@]}

        while [ "$i" -lt "$e_count" ]
        do
		check_mtime "g" "${groups[$i]}"
		ret=$?
                if [ ${ret} -eq ${E_ERROR} ] || [ ${ret} -eq ${E_CHECK_NOT_FOUND} ]; then
			save_mtime "g" "${groups[$i]}"
			ret=$?
                        do_log ${LOG_VERBOSE} ${ret} "User's \"${user}\": group \"${groups[$i]}\" saving NEW mtime (${ret})"
                fi
                let "i+=1"
        done
        return 0
}

generate_user_settings()
{
	local e_count
        local i=0

	if [ ${is_groups_loaded} -eq 0 ]; then
		load_groups
	fi

	if [ ${is_shares_loaded} -eq 0 ]; then
		load_shares
	fi

	if ( ! is_writable "${conf}/${domain}/applied/${user}" ); then
		do_log ${LOG_ERROR} ${E_CRITICAL} "Cannot write applied share file (${conf}/${domain}/applied/${user})"
		return ${E_CRITICAL}
	fi

	save_mtime "u" "${user}"
	local ret=$?
	do_log ${LOG_INFO} ${ret} "Saved user \"${user}\" mtime (${ret})"
	do_log ${LOG_VERBOSE} ${E_OK} "Saving user \"${user}\" groups \"${groups_all}\" mtimes"
	save_groups_mtimes
	ret=$?
	do_log ${LOG_INFO} ${ret} "Saved user \"${user}\" groups mtimes (${ret})"

	e_count=${#shares[@]}
	if [ ${e_count} -eq 0 ]; then
                do_log ${LOG_ERROR} ${E_WARNING} "No shares found for user (${user}) during settings generation"
                return ${E_WARNING}
        fi
	
	do_log ${LOG_VERBOSE} ${E_OK} "Saving user \"${user}\" shares \"${shares_all}\" mtimes"
	save_shares_mtimes
	ret=$?
	do_log ${LOG_INFO} ${ret} "Saved shares mtimes (${ret})"

	echo -n '' > "${conf}/${domain}/applied/${user}"
	ret=$?
	do_log ${LOG_INFO} ${ret} "Flushed user (${user}) settings"
	
	while [ "$i" -lt "$e_count" ]
        do
		do_log ${LOG_VERBOSE} ${E_OK} "Loading share (${shares[$i]}) for user (${user})"
		if [ -e "${conf}/${domain}/shares/${shares[$i]}" ]; then
			echo ";;; Loaded from ${conf}/${domain}/shares/${shares[$i]}" >> "${conf}/${domain}/applied/${user}"
			cat "${conf}/${domain}/shares/${shares[$i]}" >> "${conf}/${domain}/applied/${user}"
			echo '' >> "${conf}/${domain}/applied/${user}"
			do_log ${LOG_INFO} ${E_OK} "Loaded shares (${conf}/${domain}/shares/${shares[$i]}) to ${user} applied (${conf}/${domain}/applied/${user})"
		else
			do_log ${LOG_VERBOSE} ${E_OK} "Loading failed: share config (${shares[$i]}) does not exist!"
		fi
		let "i+=1"
        done
	
	do_log ${LOG_INFO} ${E_OK} "Saved applied user (${domain}/${user}) settings"
	
	do_log ${LOG_INFO} ${E_OK} "Reloading smbd"
	killall -SIGHUP smbd
	return ${E_OK}
}

check_domain()
{
	local dir
	local ret
	if [ -d "${conf}/${domain}" ] && [ -n "${domain}" ]; then
		do_log ${LOG_DEBUG} ${E_OK} "Domain folder exists"
		for dir in applied groups users shares mtimes md5sums caches; do
			if [ ! -d "${conf}/${domain}/${dir}" ]; then
				do_log ${LOG_ERROR} ${E_CRITICAL} "${domain}/${dir} does not exist. Trying to create."
				mkdir "${conf}/${domain}/${dir}"
				ret=$?
				if [ ${ret} -eq 1 ]; then
					do_log ${LOG_ERROR} ${E_CRITICAL} "Cannot create directory (${conf}/${domain}/${dir})"
					exit ${E_ERROR}
				else
					do_log ${LOG_VERBOSE} ${E_OK} "Created directory (${conf}/${domain}/${dir})"
				fi
			else
				do_log ${LOG_DEBUG} ${E_OK} "${domain}/${dir} OK"
			fi
		done
		do_log ${LOG_VERBOSE} ${E_OK} "Domain folder OK"
		return ${E_OK}
	elif [ -n "${domain}" ] ; then
		do_log ${LOG_ERROR} ${E_CRITICAL} "Domain folder does not exist!"
		do_log ${LOG_VERBOSE} ${E_OK} "Trying to create domain skeleton"
		mkdir "${conf}/${domain}"
		ret=$?
		if [ ${ret} -eq 1 ]; then
			do_log ${LOG_ERROR} ${ret} "Domain folder (${conf}/${domain}) creation failed"
			exit ${E_ERROR}
		else
			do_log ${LOG_VERBOSE} ${ret} "Created folder (${conf}/${domain})"
			for dir in applied groups users shares mtimes md5sums caches; do
				mkdir "${conf}/${domain}/${dir}"
				ret=$?
				if [ ${ret} -eq 1 ]; then
					do_log ${LOG_ERROR} ${ret} "Folder (${conf}/${domain}/${dir}) creation failed"
					exit ${E_ERROR}
				else
					do_log ${LOG_VERBOSE} ${ret} "Folder (${conf}/${domain}/${dir}) created"
				fi
			done
		fi
	else
		do_log ${LOG_INFO} ${E_OK} "Domain string (${domain}) empty! Exiting..."
		exit ${E_OK}
	fi
}

### MAIN ###

do_log ${LOG_VERBOSE} ${E_OK} "Got options: \"$@\""

load_vars "$@"

do_log ${LOG_INFO} ${E_OK} "Loaded: u_${user} d_${domain} m_${machine} i_${ip} ($?)"

if ( ! user_exists ); then
	do_log ${LOG_INFO} ${E_OK} "User does not exist, exiting"
	exit ${E_ERROR}
fi

check_domain

if ( config_exists ); then
	load_groups
	retur=$?
	do_log ${LOG_VERBOSE} ${retur} "Loaded groups: ${groups_all} (${retur})"
	if ( check_groups ); then
		retur=$?
		do_log ${LOG_INFO} ${retur} "Groups not changed (${retur})"
		if ( check_groups_mtimes ); then
			retur=$?
			do_log ${LOG_INFO} ${retur} "Groups mtimes not changed (${retur})"
			check_mtime "u" "${user}"
			retu=$?
			if [ ${retu} -eq ${E_OK} ] || [ ${retu} -eq ${E_FILE_NOT_FOUND} ]; then
				do_log ${LOG_INFO} ${retu} "User mtime not changed (${retu})"
				load_shares
				if ( check_shares_mtimes ); then
					do_log ${LOG_INFO} $? "Shares mtimes not changed ($?)"
				else
					do_log ${LOG_INFO} $? "Shares mtimes changed ($?)"
					generate_user_settings
				fi
			else
				do_log ${LOG_INFO} $? "User mtime changed ($?)"
				generate_user_settings
			fi
		else
			do_log ${LOG_INFO} $? "Groups mtimes changed ($?)"
			generate_user_settings
		fi
	else
		do_log ${LOG_INFO} $? "Groups changed ($?)"
		write_groups
		generate_user_settings
	fi
else
	do_log ${LOG_INFO} $? "User config does not exist ($?)"
	generate_user_settings
fi

