# Overview
Customers upgrading from a version prior to 4.2 should contact Synopsys Technical Support before proceeding.
 
# Disk Space
The data migration will temporarily require an additional free disk space at approximately 2.5 times your original database volume size to hold the database dump and the new 4.2 database volume.    As a rule-of-thumb, if the volume upon which your database resides is at least  60% free, there should be enough disk space.
 
# Database Migration
When upgrading to Black Duck version 2022.2.0 or later, database migration is done automatically.   Details are provided in the README.md doc for your particular orchestration method.
 
# External Databases
If your Black Duck instance was configured to use an external database (like Amazon RDS), administrators will need to follow the upgrade process defined by the PostgreSQL provider.  The recommended approach is to migrate your data to a 13.x instance of PostgreSQL and configure your system to point to that instance. 
 
# Contact Support
If you have any questions or concerns, please contact the Customer Support Organization to help you through this process.

