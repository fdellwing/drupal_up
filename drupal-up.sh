#!/bin/bash
######################################################
###   Script for (semi)automatic Drupal Updates    ###
###      Author: https://github.com/fdellwing      ###
###                Date: 01.12.2016                ###
###        Contact: f.dellwing@netfutura.de        ###
######################################################

######################################################
###   You may edit this values if they differ on   ###
###                  your system.                  ###
######################################################

# The root path for your drupal installations
WWW_PATH="/var/www/"

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
###          The main script starts here.          ###
######################################################

# Display usage if no parameters are given
if [ -z "$1" ]; then
    echo "Usage: ./drupal-up.sh <foldername or file>"
    echo "Instead of a foldername, you can provide a file with foldernames"
# Run the program if exactly one parameter is given
elif [ -z "$2" ]; then
	# Clear the logfiles from previous run
	date >| /var/log/drupal-mysql.log
	date >| /var/log/drupal-up.log
	# Check if the given parameter is a directory in WWW_PATH
	if [ -d "$WWW_PATH""$1" ]; then
		LIST=false
	else
		# If not, is it a file?
		if [ -e "$1" ]; then
			# Creates an array from the input file
			IFS=$'\n' drupale=( $( cat "$1" ) )
			LIST=true
		else
		# If not, exit the script
			echo "----------------------"
			echo 'The given parameter is no existing directory or file.'
			echo "----------------------"
			exit 1
		fi
	fi
	# Run the routine for a single folder
	if [ "$LIST" = false ]; then
		# Get the databases from the drupal settings
		IFS=$'\n' datenbanken=( $( grep -R -h -E "^[[:space:]]*'database' => '" "$WWW_PATH""$1"/sites/*/settings.php ) )
		TMP_PATH="$WWW_PATH""$1"
		cd "$TMP_PATH" || exit 1
		echo "----------------------"
		echo 'Starting update for '"$1"'.'
		echo "----------------------"
		# Set maintenance mode
		drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log
		# Clear the cache to make sure we are in maintenance
		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
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
			# Get that variable in the right form
			db=${db#*\'}
			db=${db#*\'}
			db=${db#*\'}
			db=${db%%\'*}
			# Dump the database in in self contained file
			mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%Y_%m_%d')".sql 2>> /var/log/drupal-mysql.log # sql file erstellen
			# shellcheck disable=SC2181
			# If the command fails, we need to stop or we can harm our drupal permanently
			if [ "$?" -eq 0 ]; then
				echo "----------------------"
				echo 'Database backup successfully created ('"$i"'/'"${#datenbanken[@]}"').'
				echo "----------------------"
			else
				echo "----------------------"
				echo 'Error while creating the database backup, please check the logfile "/var/log/drupal-mysql.log".'
				echo "----------------------"
				# Unset maintenance mode
				drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log
				# Clear the cache to make sure we are not in maintenance
				drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
				# If you are here, please read the log, because there is something wrong
				exit 1
			fi
			((i++))
		done
		echo "----------------------"
		echo 'Starting update of drupal.'
		echo "----------------------"
		# Do the drupal update
		drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log
		echo "----------------------"
		echo 'Finishing update of drupal.'
		echo "----------------------"
		# To be sure, do a DB update
		drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log
		# Set the correct owner (33=www-data)
		chown -R 33:33 "$TMP_PATH"
		# Unset maintenance mode
		drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log
		# Clear the cache to make sure we are not in maintenance
		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
		# Clear error log from previous run
		date >| /var/log/drupal-up-error.log
		# Put all the errors from the log to the error log
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log
		# Count the lines in error log >1 = there are errors
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log)
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo 'There are some errors, please check the logfile "/var/log/drupal-up-error.log"'
			echo "----------------------"
		else
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo "----------------------"
		fi
	# Run the routine for multiple drupal installations
	else
		echo "----------------------"
		echo 'Starting update for '"${#drupale[@]}"' entries.'
		echo "----------------------"
		for drupal in "${drupale[@]}"
			do
			# Get the databases from the drupal settings
			IFS=$'\n' datenbanken=( $( grep -R -h -E "^[[:space:]]*'database' => '" "$WWW_PATH""$drupal"/sites/*/settings.php ) )
			TMP_PATH="$WWW_PATH""$drupal"
			cd "$TMP_PATH" || exit 1
			echo "----------------------"
			echo 'Starting update for '"$drupal"'.'
			echo "----------------------"
			# Set maintenance mode
			drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log
			# Clear the cache to make sure we are in maintenance
			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
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
				# Get that variable in the right form
				db=${db#*\'}
				db=${db#*\'}
				db=${db#*\'}
				db=${db%%\'*} # db name 
				# Dump the database in in self contained file
				mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%Y_%m_%d')".sql 2>> /var/log/drupal-mysql.log
				# shellcheck disable=SC2181
				# If the command fails, we need to stop or we can harm our drupal permanently
				if [ "$?" -eq 0 ]; then
					echo "----------------------"
					echo 'Database backup successfully created ('"$i"'/'"${#datenbanken[@]}"').'
					echo "----------------------"
				else
					echo "----------------------"
					echo 'Error while creating the database backup, please check the logfile "/var/log/drupal-mysql.log".'
					echo "----------------------"
					# Unset maintenance mode
					drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log
					# Clear the cache to make sure we are not in maintenance
					drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
					# If you are here, please read the log, because there is something wrong
					exit 1
				fi
				((i++))
			done
			echo "----------------------"
			echo 'Starting update of drupal.'
			echo "----------------------"
			# Do the drupal update
			drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log
			echo "----------------------"
			echo 'Finishing update of drupal.'
			echo "----------------------"
			# To be sure, do a DB update
			drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log
			# Set the correct owner (33=www-data)
			chown -R 33:33 "$TMP_PATH"
			# Unset maintenance mode
			drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log
			# Clear the cache to make sure we are not in maintenance
			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo "----------------------"
		done
		# Clear error log from previous run
		date >| /var/log/drupal-up-error.log
		# Put all the errors from the log to the error log
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log
		# Count the lines in error log >1 = there are errors
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log) # fehler zählen
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then
			echo "----------------------"
			echo 'All updates finished.'
			echo 'There are some errors, please check the logfile "/var/log/drupal-up-error.log"'
			echo "----------------------"
		else
			echo "----------------------"
			echo 'All updates finished.'
			echo "----------------------"
		fi
	fi
# Display usage if more than one parameter is given
else
    echo "Usage: ./drupal-up.sh <foldername or file>"
    echo "Instead of a foldername, you can provide a file with foldernames"
fi
