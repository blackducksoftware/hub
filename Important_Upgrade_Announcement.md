# Overview
Customers upgrading from a version prior to 4.2, will need to perform a data migration as part of their upgrade process.  The detailed instructions are in the README.md doc file in the folder for the orchestration method  you used in your hub installation.   If you are performing a new install, these steps are not required.
 
# Disk Space
The data migration will temporarily require an additional free disk space at approximately 2.5 times your original database volume size to hold the database dump and the new 4.2 database volume.    As a rule-of-thumb, if the volume upon which your database resides is at least  60% free, there should be enough disk space.
 
# Upgrade Steps
At a high level, the steps are as follows.   Actual commands to run the steps are located in the README.md doc for your particular orchestration method.
 
1. Verify Disk space.  (see above)
 
2. Bring down the Hub containers - Use the appropriate commands per your orchestration type to bring down your Hub instance.   This is  done to ensure no one is writing to the database during the migration procedure.
 
3. Start the currently installed Hub (prior to version 4.2) in data migration mode -  For each orchestration method, a configuration file is provided to only start the containers needed for the migration.  Use  that file to bring up those containers.   This will start the only the database containers needed for the dump.
 
4. Create a dump of the database – use the provided script and commands listed in the README.md file to create the database dump. 
 
5. Bring Down the data migration mode containers – once the dump is complete, use the appropriate commands as documented for your orchestration method to bring down the database migration containers.
 
6. Using the new orchestration files, start the version of the Hub to which you migrating in data migration mode.   This will pull  the new images and upgrade the database software. 
 
7. Using the provided scripts, restore the database dump from step 4
 
8. Bring down the data migration mode containers
 
9. Using the new orchestration files, start the new version of the Hub to which your are upgrading (i.e 4.2 or later)
 
10. Verify that the data is migrated and the Hub is on the upgraded version
 
11. Once everything looks good, you can remove the old data volume
 
If you perform the upgrade without migrating the data, the upgrade will successfully complete, however, the system will be left with an empty database as the data was not migrated.  If this does occur, the data is safe in the old volume, however, administrators need will perform the migration to before the old data can be accessed in the Hub application.
 
# External Databases
If your Hub instance was configured to use an external database (like Amazon RDS), administrators will essentially need to do the same thing.  The recommended approach is to migrate your data to a 9.6 instance of PostgreSQL and configure your system to point to that instance.   If an administrator attempts to perform an upgrade to Hub 4.2 on a system that is connected to a non-9.6 PostgreSQL database, the application will fail to start, however the data remains safe. 
 
# Contact Support
If you have any questions or concerns, please contact the Customer Support Organization to help you through this process.

