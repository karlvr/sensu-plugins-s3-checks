#!/bin/bash -eu
#
# Check S3 file age using aws-cli

usage() {
	echo "usage: $0 [-a <access_key>] [-s <secret_key>] [-r <region>] <url>" >&2
	echo >&2
	echo "Environment variables:" >&2
	echo "AWS_ACCESS_KEY_ID" >&2
	echo "AWS_SECRET_ACCESS_KEY" >&2
	echo "AWS_REGION" >&2
}

AWS=aws

if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
	echo "Missing AWS_ACCESS_KEY_ID" >&2
	usage
	exit 3
fi
if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
	echo "Missing AWS_SECRET_ACCESS_KEY" >&2
	usage
	exit 3
fi
if [ -z "${AWS_REGION:-}" ]; then
	echo "Missing AWS_REGION" >&2
	usage
	exit 3
fi

SCHEME="$(hostname).s3"

while getopts ":s:" opt; do
  case $opt in
    s)
      SCHEME="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
	  exit 3
      ;;
  esac
done

shift $((OPTIND-1))

MODULE_NAME="S3_AGE"

NOW=$(date +%s)
TOTAL_WARNINGS=0
TOTAL_CRITICALS=0

for URL in $* ; do
	CHECK_COMMAND="\$AWS s3 ls \"\$URL\""

	WARNINGS=0
	CRITICALS=0

	set +e
	check_output=$(eval $CHECK_COMMAND)
	STATUS=$?
	if [ $STATUS != 0 ]; then
		echo "$MODULE_NAME CRITICAL: aws cli error $STATUS listing $URL, probably no files found"
		TOTAL_CRITICALS=$(($TOTAL_CRITICALS + 1))
		continue
	fi

	echo "$check_output" | (
		while read LINE ; do
			DATE_STRING=$(echo "$LINE" | awk '{ print $1 " " $2 }')
			SIZE=$(echo "$LINE" | awk '{ print $3 }')
			FILE=$(echo "$LINE" | awk '{ print $4 }')
			NAME=${FILE//./_}

			echo "$SCHEME.$NAME.size $SIZE $NOW"

			if [[ "$OSTYPE" =~ ^darwin ]]; then
				DATE=$(date -jf "%Y-%m-%d %H:%M:%S" "${DATE_STRING}" "+%s")
			else
				DATE=$(date -d "$DATE_STRING" +%s)
			fi
			
			if [ $? != 0 ]; then
				echo "$MODULE_NAME CRITICAL: $FILE: failed to parse date: $DATE_STRING"
				CRITICALS=$(($CRITICALS + 1))
			else
				AGE=$(($NOW - $DATE))
				echo "$SCHEME.$NAME.age $AGE $NOW"
			fi
		done

		if [ $CRITICALS != 0 ]; then
			exit 2
		elif [ $WARNINGS != 0 ]; then
			exit 1
		fi
	)

	STATUS=$?
	if [ $STATUS == 2 ]; then
		TOTAL_CRITICALS=$(($TOTAL_CRITICALS + 1))
	elif [ $STATUS == 1 ]; then
		TOTAL_WARNINGS=$(($TOTAL_WARNINGS + 1))
	fi
done

if [ $TOTAL_CRITICALS != 0 ]; then
	exit 2
elif [ $TOTAL_WARNINGS != 0 ]; then
	exit 1
fi
