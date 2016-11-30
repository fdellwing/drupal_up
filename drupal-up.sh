#!/bin/bash
######################################################
###   Script for (semi)automatic Drupal Updates    ###
###      Author: https://github.com/fdellwing      ###
###                Date: 26.07.2016                ###
###        Contact: f.dellwing@netfutura.de        ###
######################################################

WWW_PATH="/var/www/" # you may edit this if ur www path is different
CONF="/etc/mysql/debian.cnf" # mysql config einlesen

if [ -z "$1" ]; then
    # display usage if no parameters given
    echo "Usage: ./drupal-up.sh <folder or list>"
    echo "Instead of a folder, you can provide a list with folder names"
elif [ -z "$2" ]; then
	date >| /var/log/drupal-mysql.log # clear logfile
	date >| /var/log/drupal-up.log # clear logfile
	if [ -d "$WWW_PATH""$1" ]; then # is the given parameter a directory?
		LIST=false
	else # no!
		if [ -e "$1" ]; then # is it a file?
			# Liest die angegebene Datei in das Array drupale
			IFS=$'\n' drupale=( $( cat "$1" ) )
			LIST=true
		else # no!
			echo "----------------------"
			echo 'The given parameter is no existing directory or file.'
			echo "----------------------"
			exit 1 # script beenden
		fi
	fi
	if [ "$LIST" = false ]; then # für einen ordner
		IFS=$'\n' datenbanken=( $( grep -R -h "'database' => 'drupal_" "$WWW_PATH""$1"/sites/*/settings.php ) )
		TMP_PATH="$WWW_PATH""$1" # wir gehen in den drupal ordner
		cd "$TMP_PATH" || exit 1
		echo "----------------------"
		echo 'Starting update for '"$1"'.'
		echo "----------------------"
		drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus setzen
		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
		echo "----------------------"
		echo 'Site(s) moved to maintenance mode.'
		echo "----------------------"
		echo "----------------------"
		echo 'Starting '"${#datenbanken[@]}"' database backup(s).'
		echo "----------------------"
		# shellcheck disable=SC2034
		i=1
		for db in "${datenbanken[@]}"
			do
			db=${db#*\'}
			db=${db#*\'}
			db=${db#*\'}
			db=${db%%\'*} # datenbank name 
			mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%Y_%m_%d')".sql 2>> /var/log/drupal-mysql.log # sql file erstellen
			# shellcheck disable=SC2181
			if [ "$?" -eq 0 ]; then # fehlerfrei?
				echo "----------------------"
				echo 'Database backup successfully created ('"$i"'/'"${#datenbanken[@]}"').'
				echo "----------------------"
			else # nein!
				echo "----------------------"
				echo 'Error while creating the database backup, please check the logfile "/var/log/drupal-mysql.log".'
				echo "----------------------"
				drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
				drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
				exit 1 # script beenden
			fi
			((i++))
		done
		echo "----------------------"
		echo 'Starting update of drupal.'
		echo "----------------------"
		drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log # drupal update
		echo "----------------------"
		echo 'Finishing update of drupal.'
		echo "----------------------"
		drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log # drupal updatedb
		chown -R 33:33 "$TMP_PATH" # alles www-data geben
		drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
		date >| /var/log/drupal-up-error.log # logdatei leeren
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log # nur fehler ausgeben
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log) # fehlerzahl lesen
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then # haben wir fehler?
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo 'There are some errors, please check the logfile "/var/log/drupal-up-error.log"'
			echo "----------------------"
		else # nein!
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo "----------------------"
		fi
	else # für mehrere ordner
		echo "----------------------"
		echo 'Starting update for '"${#drupale[@]}"' entries.'
		echo "----------------------"
		for drupal in "${drupale[@]}"
			do
			IFS=$'\n' datenbanken=( $( grep -R -h "'database' => 'drupal_" /var/www/"$drupal"/sites/*/settings.php ) )
			TMP_PATH="$WWW_PATH""$drupal"
			cd "$TMP_PATH" || exit 1 # ins drupal verzeichnis wechseln
			echo "----------------------"
			echo 'Starting update for '"$drupal"'.'
			echo "----------------------"
			drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus setzen
			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
			echo "----------------------"
			echo 'Site(s) moved to maintenance mode.'
			echo "----------------------"
			echo "----------------------"
			echo 'Starting '"${#datenbanken[@]}"' database backup(s).'
			echo "----------------------"
			# shellcheck disable=SC2034
			i=1
			for db in "${datenbanken[@]}"
				do
				db=${db#*\'}
				db=${db#*\'}
				db=${db#*\'}
				db=${db%%\'*} # db name 
				mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%Y_%m_%d')".sql 2>> /var/log/drupal-mysql.log # datenbank sichern
				# shellcheck disable=SC2181
				if [ "$?" -eq 0 ]; then # fehlerfrei?
					echo "----------------------"
					echo 'Database backup successfully created ('"$i"'/'"${#datenbanken[@]}"').'
					echo "----------------------"
				else # nein!
					echo "----------------------"
					echo 'Error while creating the database backup, please check the logfile "/var/log/drupal-mysql.log".'
					echo "----------------------"
					drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
					drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
					exit 1 # script beenden
				fi
				((i++))
			done
			echo "----------------------"
			echo 'Starting update of drupal.'
			echo "----------------------"
			drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log # drupal update
			echo "----------------------"
			echo 'Finishing update of drupal.'
			echo "----------------------"
			drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log # drupal updatedb
			chown -R 33:33 "$TMP_PATH" # alles www-data geben
			drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
			echo "----------------------"
			echo 'Site(s) moved out of maintenance mode, please check the website(s).'
			echo "----------------------"
		done
		date > /var/log/drupal-up-error.log # log leeren
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log # nur fehler schreiben
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log) # fehler zählen
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then # mehr als 1 fehler?
			echo "----------------------"
			echo 'All updates finished.'
			echo 'There are some errors, please check the logfile "/var/log/drupal-up-error.log"'
			echo "----------------------"
		else # nein!
			echo "----------------------"
			echo 'All updates finished.'
			echo "----------------------"
		fi
	fi
else
    # display usage if wrong parameters given
    echo "Usage: ./drupal-up.sh <folder or list>"
    echo "Instead of a folder, you can provide a list with folder names"
fi