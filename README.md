# drupal_up

[![Build Status](https://travis-ci.org/fdellwing/drupal_up.svg?branch=master)](https://travis-ci.org/fdellwing/drupal_up)[![Type](https://img.shields.io/badge/type-%2Fbin%2Fbash-blue.svg)](https://www.gnu.org/software/bash/bash.html)

This script is your easy way to do your drupal updates.

**Why (semi-)automatic and not automatic?**

Well, thats simple. With every update there is the chance that it will break your site. So you need to check the site after each and every update if everything works as intended.
I personally run this script directly from console and check every site directly after the scripts says so. But you can also trigger this script via cron and check some time afterwards.

**Thats the use of this script?**

Well, thats also simple. To run updates on multiple installations you need a lot of time and nervs. Setting maintenance, getting a DB backup, etc. With this script, all that is done by a single command.

**Foldername or file?**

You can update each installation individually by triggering the script on the foldername of the drupal installation. But you can also put multiple foldernames in a file and the script will update all these installations.

Example:
```shell
drupal1
drupal2
drupal3
```

**Usage**
```shell
    Usage: ./drupal-up.sh <foldername or file>
    Instead of a foldername, you can provide a file with foldernames
```

**Footnote**

Feel free to fork, modify or improve this script. I will also look at every pull request.