#!/bin/bash -eu
#
# Check S3 file age using aws-cli

usage() {
	echo "usage: $0 [-w <warning age>] [-W <warning size>] [-c <critical age>] [-C <critical size>] " >&2
	echo "          <url>" >&2
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

WARNING_AGE=0
CRITICAL_AGE=0
WARNING_SIZE=0
CRITICAL_SIZE=0

while getopts ":w:W:c:C:" opt; do
  case $opt in
	w)
	  WARNING_AGE="$OPTARG"
	  ;;
	W)
      WARNING_SIZE="$OPTARG"
      ;;
    c)
      CRITICAL_AGE="$OPTARG"
      ;;
    C)
      CRITICAL_SIZE="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
	  exit 3
      ;;
  esac
done

shift $((OPTIND-1))

MODULE_NAME="S3_AGE"

if [ $WARNING_AGE == 0 -a $CRITICAL_AGE == 0 ]; then
	WARNING_AGE=93600 # 26 hours (to allow 2 hours to generate a file daily)
	CRITICAL_AGE=172800 # 48 hours
fi

#echo "WARNING_AGE=$WARNING_AGE WARNING_SIZE=$WARNING_SIZE CRITICAL_AGE=$CRITICAL_AGE CRITICAL_SIZE=$CRITICAL_SIZE" >&2

NOW=$(date +%s)
TOTAL_WARNINGS=0
TOTAL_CRITICALS=0

for URL in $* ; do
	CHECK_COMMAND="\$AWS s3 ls \"\$URL\""

	LINES=0
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
			if [ -z "$LINE" ]; then
				continue
			fi

			LINES=$(($LINES + 1))
			DATE_STRING=$(echo "$LINE" | awk '{ print $1 " " $2 }')
			SIZE=$(echo "$LINE" | awk '{ print $3 }')
			FILE=$(echo "$LINE" | awk '{ print $4 }')

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

				if [ $? != 0 ]; then
					echo "$MODULE_NAME CRITICAL: $FILE: failed to parse date: $DATE_STRING"
					CRITICALS=$(($CRITICALS + 1))
				elif [ $CRITICAL_SIZE != 0 -a $(($SIZE < $CRITICAL_SIZE)) != 0 ]; then
					echo "$MODULE_NAME CRITICAL: $FILE: size $SIZE < $CRITICAL_SIZE"
					CRITICALS=$(($CRITICALS + 1))
				elif [ $CRITICAL_AGE != 0 -a $(($AGE > $CRITICAL_AGE)) != 0 ]; then
					echo "$MODULE_NAME CRITICAL: $FILE: age $AGE > $CRITICAL_AGE"
					CRITICALS=$(($CRITICALS + 1))
				elif [ $WARNING_SIZE != 0 -a $(($SIZE < $WARNING_SIZE)) != 0 ]; then
					echo "$MODULE_NAME WARNING: $FILE: size $SIZE < $WARNING_SIZE"
					WARNINGS=$(($WARNINGS + 1))
				elif [ $WARNING_AGE != 0 -a $(($AGE > $WARNING_AGE)) != 0 ]; then
					echo "$MODULE_NAME WARNING: $FILE: age $AGE > $WARNING_AGE"
					WARNINGS=$(($WARNINGS + 1))
				else
					echo "$MODULE_NAME OK: $FILE is $AGE seconds old and $SIZE bytes"
				fi
			fi
		done

		if [ $CRITICALS != 0 ]; then
			exit 2
		elif [ $WARNINGS != 0 ]; then
			exit 1
		elif [ $LINES == 0 ]; then
			echo "$MODULE_NAME UNKNOWN: No files found at $URL"
			exit 3
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
