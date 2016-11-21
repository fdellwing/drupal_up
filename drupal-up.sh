#!/bin/bash
################################################################
###       Script für (halb)automatische Drupal Updates       ###
###           Autor: Fabian Dellwing, Stephan Sauer          ###
###                    Datum: 26.07.2016                     ###
###             Kontakt: f.dellwing@netfutura.de             ###
################################################################

MY_PATH=$(dirname "$0") # relative
MY_PATH=$(cd "$MY_PATH" && pwd) # absolutized and normalized
if [ -z "$MY_PATH" ] ; then
	# error; for some reason, the path is not accessible
	# to the script (e.g. permissions re-evaled after suid)
	exit 1  # fail
fi
cd "$MY_PATH" || exit 1

if [ -z "$1" ]; then
    # display usage if no parameters given
    echo "Usage: ./drupal-up.sh <folder or list>"
    echo "Instead of a folder, you can provide a list with folder names"
elif [ -z "$2" ]; then
	date > /var/log/drupal-mysql.log # clear logfile

	date > /var/log/drupal-up.log # clear logfile

	WWW_PATH="/var/www/" # you may edit this if ur www path is different

	if [ -d "$WWW_PATH""$1" ]; then # ist der angegebene parameter ein ordner?
		LIST=false
	else # nein!
		if [ -e "$1" ]; then # ist es eine datei?
			# Liest die angegebene Datei in das Array drupale
			IFS=$'\n' drupale=( $( cat "$1" ) )
			LIST=true
		else # nein!
			echo "----------------------"
			echo 'Angegebener Parameter ist kein existierender Ordner oder Datei.'
			echo "----------------------"
			exit 1 # script beenden
		fi
	fi


	if [ "$LIST" = false ]; then # für einen ordner
	
		SITECOUNT=$(find ./* -maxdepth 0 -type d | wc -l)
		if [ "$SITECOUNT" -gt 2 ]; then # ist es ein multisite setup?
			IFS=$'\n' datenbanken=( $( grep -R -h "'database' => 'drupal_" /var/www/"$1"/sites/*/settings.php ) )
			DB_LIST=true
		else # nein!
			MY_DB_NAME="drupal_""$1"
			MY_DB_NAME=$(echo "$MY_DB_NAME" | tr \- \_)
			DB_LIST=false
		fi
		
		TMP_PATH="$WWW_PATH""$1" # wir gehen in den drupal ordner
		cd "$TMP_PATH" || exit 1
		echo "----------------------"
		echo 'Starte Updateroutine für '"$1"'.'
		echo "----------------------"
		drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus setzen
		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
		echo "----------------------"
		echo 'Seite(n) in den Wartungsmodus versetzt.'
		echo "----------------------"
		echo "----------------------"
		echo "Starte Datenbank Sicherung."
		echo "----------------------"
		CONF="/etc/mysql/debian.cnf" # mysql config einlesen
		if [ "$DB_LIST" = true ]; then # multisite?
			for db in "${datenbanken[@]}"
				do
				db=${db#*\'}
				db=${db#*\'}
				db=${db#*\'}
				db=${db%%\'*} # datenbank name 
				mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%m_%d_%Y')".sql 2>> /var/log/drupal-mysql.log # sql file erstellen
				if [ "$?" -eq 0 ]; then # fehlerfrei?
					echo "----------------------"
					echo "Datenbank Sicherung erfolgreich erstellt."
					echo "----------------------"
				else # nein!
					echo "----------------------"
					echo 'Fehler bei der Erstellung der Datenbanksicherung, siehe Logfile "/var/log/drupal-mysql.log".'
					echo "----------------------"
					drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
					drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
					exit 1 # script beenden
				fi
			done
		else # nein!
			mysqldump --defaults-extra-file="$CONF" --add-drop-table "$MY_DB_NAME" > /root/drupal_update_db_back/"$MY_DB_NAME""_""$(date +'%m_%d_%Y')".sql 2>> /var/log/drupal-mysql.log #sql file erstellen
			if [ "$?" -eq 0 ]; then # fehlerfrei?
				echo "----------------------"
				echo "Datenbank Sicherung erfolgreich erstellt."
				echo "----------------------"
			else # nein!
				echo "----------------------"
				echo 'Fehler bei der Erstellung der Datenbanksicherung, siehe Logfile "/var/log/drupal-mysql.log".'
				echo "----------------------"
				drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log
				drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log
				exit 1 # script beenden
			fi
		fi
		echo "----------------------"
		echo 'Starte Update des Drupalsystems.'
		echo "----------------------"
		drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log # drupal update

		echo "----------------------"
		echo 'Finalisiere Update des Drupalsystems.'
		echo "----------------------"
		drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log # drupal updatedb

		chown -R 33:33 "$TMP_PATH" # alles www-data geben
		drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen

		drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
		
		date > /var/log/drupal-up-error.log # logdatei leeren
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log # nur fehler ausgeben
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log) # fehlerzahl lesen
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then # haben wir fehler?
			echo "----------------------"
			echo 'Seite(n) aus dem Wartungsmodus genommen, bitte Webseite überprüfen.'
			echo 'Es sind Fehler aufgetreten, bitte unter "/var/log/drupal-up-error.log" nachschauen.'
			echo "----------------------"
		else # nein!
			echo "----------------------"
			echo 'Seite(n) aus dem Wartungsmodus genommen, bitte Webseite überprüfen.'
			echo "----------------------"
		fi
	else # für mehrere ordner
		echo "----------------------"
		echo 'Starte Updateroutinen für '${#drupale[@]}' Einträge.'
		echo "----------------------"
		for drupal in "${drupale[@]}"
			do
			SITECOUNT=$(find ./* -maxdepth 0 -type d | wc -l)
			if [ "$SITECOUNT" -gt 2 ]; then # ist es multisite?
				IFS=$'\n' datenbanken=( $( grep -R -h "'database' => 'drupal_" /var/www/"$drupal"/sites/*/settings.php ) )
				DB_LIST=true
			else # nein!
				if [ "$drupal" = "schnellfein" ]; then # hardcoded ausnahme
					MY_DB_NAME="$drupal"
					DB_LIST=false
				elif [ "$drupal" = "ars-werbe" ]; then # hardcoded ausnahme
					MY_DB_NAME="drupal_asr-werben"
					DB_LIST=false
				else # standard db shema: drupal_ordner
					MY_DB_NAME="drupal_""$drupal"
					MY_DB_NAME=$(echo "$MY_DB_NAME" | tr \- \_)
					DB_LIST=false
				fi
			fi
			
			TMP_PATH="$WWW_PATH""$drupal"
			cd "$TMP_PATH" || exit 1 # ins drupal verzeichnis wechseln
			echo "----------------------"
			echo 'Starte Updateroutine für '"$drupal"'.'
			echo "----------------------"
			drush @sites vset maintenance_mode 1 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus setzen
			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
			echo "----------------------"
			echo 'Seite(n) in den Wartungsmodus versetzt.'
			echo "----------------------"
			echo "----------------------"
			echo "Starte Datenbank Sicherung."
			echo "----------------------"
			CONF="/etc/mysql/debian.cnf"
			if [ "$DB_LIST" = true ]; then # multisite?
				for db in "${datenbanken[@]}"
					do
					db=${db#*\'}
					db=${db#*\'}
					db=${db#*\'}
					db=${db%%\'*} # db name 
					mysqldump --defaults-extra-file="$CONF" --add-drop-table "$db" > /root/drupal_update_db_back/"$db""_""$(date +'%m_%d_%Y')".sql 2>> /var/log/drupal-mysql.log # datenbank sichern
					if [ "$?" -eq 0 ]; then # fehlerfrei?
						echo "----------------------"
						echo "Datenbank Sicherung erfolgreich erstellt."
						echo "----------------------"
					else # nein!
						echo "----------------------"
						echo 'Fehler bei der Erstellung der Datenbanksicherung, siehe Logfile "/var/log/drupal-mysql.log".'
						echo "----------------------"
						drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
						drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
						exit 1 # script beenden
					fi
				done
			else # nein!
				mysqldump --defaults-extra-file="$CONF" --add-drop-table "$MY_DB_NAME" > /root/drupal_update_db_back/"$MY_DB_NAME""_""$(date +'%m_%d_%Y')".sql 2>> /var/log/drupal-mysql.log # datenbank sichern
				if [ "$?" -eq 0 ]; then # fehlerfrei ?
					echo "----------------------"
					echo "Datenbank Sicherung erfolgreich erstellt."
					echo "----------------------"
				else # nein!
					echo "----------------------"
					echo 'Fehler bei der Erstellung der Datenbanksicherung, siehe Logfile "/var/log/drupal-mysql.log".'
					echo "----------------------"
					drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen
					drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
					exit 1 # script beenden
				fi
			fi
			echo "----------------------"
			echo 'Starte Update des Drupalsystems.'
			echo "----------------------"
			drush @sites up -y >> /dev/null 2>> /var/log/drupal-up.log # drupal update

			echo "----------------------"
			echo 'Finalisiere Update des Drupalsystems.'
			echo "----------------------"
			drush @sites updatedb -y >> /dev/null 2>> /var/log/drupal-up.log # drupal updatedb

			chown -R 33:33 "$TMP_PATH" # alles www-data geben
			drush @sites vset maintenance_mode 0 -y >> /dev/null 2>> /var/log/drupal-up.log # wartungsmodus entfernen

			drush @sites cc all -y >> /dev/null 2>> /var/log/drupal-up.log # cache clearen
			echo "----------------------"
			echo 'Seite(n) aus dem Wartungsmodus genommen, bitte Webseite überprüfen.'
			echo "----------------------"
		done
		
		date > /var/log/drupal-up-error.log # log leeren
		grep error /var/log/drupal-up.log >> /var/log/drupal-up-error.log # nur fehler schreiben
		LINECOUNT=$(wc -l /var/log/drupal-up-error.log) # fehler zählen
		LINECOUNT=${LINECOUNT%% *}
		if [ "$LINECOUNT" -gt 1 ]; then # mehr als 1 fehler?
			echo "----------------------"
			echo 'Sämtliche Updateroutinen beendet.'
			echo 'Es sind Fehler aufgetreten, bitte unter "/var/log/drupal-up-error.log" nachschauen.'
			echo "----------------------"
		else # nein!
			echo "----------------------"
			echo 'Sämtliche Updateroutinen beendet.'
			echo "----------------------"
		fi
	fi
else
    # display usage if wrong parameters given
    echo "Usage: ./drupal-up.sh <folder or list>"
    echo "Instead of a folder, you can provide a list with folder names"
fi