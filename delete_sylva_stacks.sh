#!/bin/sh

# some error codes so that the script will fail fast

NO_RC_FILE=2
NO_OPENSTACK_CLEANUP_RETRIEVED=3
NO_PROJECTS_LIST=4
NO_STACK_LIST=5

# MANDATORY dependencies

source ./openrc || exit "${NO_RC_FILE}"
CLEANUP_SCRIPT="./openstack-cleanup.sh"
CLEANUP_SCRIPT_URL_PATH="https://gitlab.com/sylva-projects/sylva-core/-/raw/main/tools/openstack-cleanup.sh"

if [ -e "${CLEANUP_SCRIPT}" ] ; then
	rm -rf "${CLEANUP_SCRIPT}"
else
 	if wget -O "${CLEANUP_SCRIPT}" "${CLEANUP_SCRIPT_URL_PATH}" ; then
		chmod +x "${CLEANUP_SCRIPT}"
	
	else
		exit "${NO_OPENSTACK_CLEANUP_RETRIEVED}"
	fi
fi

# setting default cleanup period for 30 days, unless specified by the user
[[ -z $1 ]] && NUM_DAYS=30 || NUM_DAYS=$1

# computing the delete threshold in seconds
THRESHOLD=$(( NUM_DAYS *  24 * 60 * 60 ))

TAGS=$(mktemp)
EXCLUDED_TAGS=$(mktemp)
LOOKUP_TAGS=$(mktemp)
ALL_PROJECTS=$(openstack project list -f json -c Name | jq -r .[].Name) || exit "${NO_PROJECTS_LIST}" 
ALL_STACKS=$(openstack stack list -f json -c ID -c "Stack Name" -c Project -c "Creation Time" | jq -r '.[]' | jq -r '.ID,."Stack Name",.Project,."Creation Time"' | xargs -n 4 | grep -E '(management|workload)') || exit "${NO_STACK_LIST}"

while read stack_id stack_name project_name creation_time; do
	creation_time_epoch=$(date --date="${creation_time}" +%s)
	now=$(date +%s)
	seconds_elapsed=$(( now - creation_time_epoch ))
	if [[ "${seconds_elapsed}" -lt "${THRESHOLD}" ]] ; then
		openstack stack show "${stack_id}" -f json -c tags | jq -r '.tags[]' 2>/dev/null >> "${TAGS}"
	else	
		openstack stack show "${stack_id}" -f json -c tags | jq -r '.tags[]' 2>/dev/null >> "${EXCLUDED_TAGS}"
	fi
done <<< "$(echo "${ALL_STACKS}")"

cat "${TAGS}" | sort -u > $(echo "${TAGS}")
cat "${EXCLUDED_TAGS}" | sort -u > $(echo "${EXCLUDED_TAGS}")
comm -3 -2 "$(echo "${TAGS}")" "$(echo "${EXCLUDED_TAGS}")" >> $(echo "${LOOKUP_TAGS}")


### MAIN
echo "*** The script will try to delete the stacks by looping over the following tags***"
cat "${LOOKUP_TAGS}"
echo "=================================================================================="
for tag in $(cat "${LOOKUP_TAGS}") ; do
	echo "./openstack-cleanup.sh --os-cloud admin $tag"
done
