#!/bin/bash
######################################################
###   Script for (semi)automatic Drupal Updates    ###
###      Author: https://github.com/fdellwing      ###
###                Date: 03.06.2019                ###
###        Contact: f.dellwing@netfutura.de        ###
######################################################

######################################################
###   You may edit this values if they differ on   ###
###                  your system.                  ###
######################################################

# The root path for your drupal installations
WWW_PATH="/var/www/"
# Database backup directory
DB_BACKUP_PATH="/root/drupal_update_db_back/"
# Log file directory
LOG_PATH="/var/log/"
# Drupal files owner (33=www-data)
OID=33
# Drupal files group (33=www-data)
GID=33

# Your systems MYSQL user settings
# If you do not use a debian based system,
# the file has to look like this:
# [client]
# host     = localhost
# user     = debian-sys-maint
# password = passphrase
# socket   = /var/run/mysqld/mysqld.sock
CONF="/etc/mysql/debian.cnf"

######################################################
###     Important functions used by the script     ###
######################################################

function set_maintenance {
	if [ "$D_VERSION" -eq 7 ]; then
		# Set maintenance mode
		drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		# Clear the cache to make sure we are in maintenance
		drush @sites cc all -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log # clear cache
	else
		# Set maintenance mode
		drush @sites sset system.maintenance_mode 1 -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		# Clear the cache to make sure we are in maintenance
		drush @sites cr -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log # clear cache
	fi
}

function unset_maintenance {
	if [ "$D_VERSION" -eq 7 ]; then
		# Unset maintenance mode
		drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		# Clear the cache to make sure we are not in maintenance
		drush @sites cc all -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log # clear cache
	else
		# Unset maintenance mode
		drush @sites sset system.maintenance_mode 0 -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		# Clear the cache to make sure we are not in maintenance
		drush @sites cr -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log # clear cache
	fi
}

######################################################
###          The main script starts here.          ###
######################################################

# Display usage if no parameters are given
if [ -z "$1" ]; then
    echo "Usage: ./drupal-up.sh <foldername or file>"
    echo "Instead of a foldername, you can provide a file with foldernames"
# Run the program if exactly one parameter is given
elif [ -z "$2" ]; then
	# Delete old db backups
	find "$DB_BACKUP_PATH" -iname "*" -mtime +90 -delete 2> /dev/null || mkdir -p "$DB_BACKUP_PATH"
	# Clear the logfiles from previous run
	if [ ! -d "$LOG_PATH" ]; then
		mkdir -p "$LOG_PATH"
	fi
	date >| "$LOG_PATH"drupal-mysql.log
	date >| "$LOG_PATH"drupal-up.log
	# Check if the given parameter is a directory in WWW_PATH
	if [ -d "$WWW_PATH""$1" ]; then
		drupale=( "$1" )
	else
		# If not, is it a file?
		if [ -e "$1" ]; then
			# Creates an array from the input file
			drupale=()
			while IFS=$'\n' read -r line; do drupale+=("$line"); done < <(cat "$1")
		else
			# If not, exit the script
			echo "----------------------"
			echo 'The given parameter is no existing directory or file.'
			echo "----------------------"
			exit 1
		fi
	fi
	echo "----------------------"
	echo 'Starting update for '"${#drupale[@]}"' instances.'
	echo "----------------------"
	for drupal in "${drupale[@]}"
		do
		# Get the databases from the drupal settings
		datenbanken=()
		while IFS=$'\n' read -r line; do datenbanken+=("$line"); done < <(grep -R -h -E "^[[:space:]]*'database' => '" "$WWW_PATH""$drupal"/sites/*/settings.php | grep -Po "(?<==> ').*(?=')")
		TMP_PATH="$WWW_PATH""$drupal"
		cd "$TMP_PATH" || exit 1
		D_VERSION=$(drush @sites status -y --format=json 2> /dev/null | grep 'drupal-version' | grep -Eo '[0-9]+\.' | head -c 1)
		echo "----------------------"
		echo 'Starting update for '"$drupal"'.'
		echo "----------------------"
		set_maintenance
		echo "----------------------"
		echo 'Site(s) moved to maintenance mode.'
		echo "----------------------"
		echo "----------------------"
		echo 'Starting '"${#datenbanken[@]}"' database backup(s).'
		echo "----------------------"
		# shellcheck disable=SC2034
		i=1
		# Create the DB backups
		for db in "${datenbanken[@]}"
			do
			# Dump the database in in self contained file
			# If the command fails, we need to stop or we can harm our drupal permanently
			if mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" | gzip > "$DB_BACKUP_PATH""$db""_""$(date +'%Y_%m_%d')".sql.gz 2>> "$LOG_PATH"drupal-mysql.log; then
				echo "----------------------"
				echo 'Database backup successfully created ('"$i"'/'"${#datenbanken[@]}"').'
				echo "----------------------"
			else
				echo "----------------------"
				echo "Error while creating the database backup, please check the logfile \"$LOG_PATH""drupal-mysql.log\"."
				echo "----------------------"
				unset_maintenance
				# If you are here, please read the log, because there is something wrong
				exit 1
			fi
			((i++))
		done
		echo "----------------------"
		echo 'Starting update of drupal.'
		echo "----------------------"
		# Do the drupal update
		drush @sites rf -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		drush @sites up -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		echo "----------------------"
		echo 'Finishing update of drupal.'
		echo "----------------------"
		# To be sure, do a DB update
		drush @sites updatedb -y >> /dev/null 2>> "$LOG_PATH"drupal-up.log
		# Set the correct owner
		chown -R $OID:$GID "$TMP_PATH"
		unset_maintenance
		echo "----------------------"
		echo 'Site(s) moved out of maintenance mode, please check the website(s).'
		echo "----------------------"
	done
	# Clear error log from previous run
	date >| "$LOG_PATH"drupal-up-error.log
	# Put all the errors from the log to the error log
	grep error "$LOG_PATH"drupal-up.log >> "$LOG_PATH"drupal-up-error.log
	# Count the lines in error log >1 = there are errors
	LINECOUNT=$(wc -l "$LOG_PATH"drupal-up-error.log | cut -f1 -d' ')
	if [ "$LINECOUNT" -gt 1 ]; then
		echo "----------------------"
		echo 'All updates finished.'
		echo "There are some errors, please check the logfile \"$LOG_PATH""drupal-up-error.log\"."
		echo "----------------------"
	else
		echo "----------------------"
		echo 'All updates finished.'
		echo "----------------------"
	fi
# Display usage if more than one parameter is given
else
    echo "Usage: ./drupal-up.sh <foldername or file>"
    echo "Instead of a foldername, you can provide a file with foldernames"
fi
