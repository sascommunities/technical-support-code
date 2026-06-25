# transfer_viya.py Script Documentation
This script is a replacement for the transfer_viya.sh shell script which made use of the SAS Admin CLI / SAS Viya CLI. This script uses the python requests module to call the various REST APIs for Viya directly, though it still makes use of the CLI's profiles to resolve the base URL for the environment and manage authentication.

The main purpose of this script and its predecessor was to avoid out of memory conditions that can occur in the transfer service when exporting lots of content. For example, while exporting /Users through the transfer service directly would produce a single large package of all content for all users, use of this script would create a separate export for each user's folder, and to optionally import those packages to a target environment.

Additional functionality was added to:
- Export all content of a given type rather than using a folder (e.g. export all reports) 
- Export indivdual non-folder objects in supplied parent folder
- Export all member objects of a given folder (i.e. not limited to just folder children of a folder)
- UserMigrate - Migrate SAS Logon user definitions from the source to the target to address issues that can arise from importing some objects if the owning user has never logged in to the target.
- EmptyRB - Empty (remove) users' recycle bins to avoid exporting unnecessary data (source) or causing an imported object to be imported into the recycle bin (if it was moved to the recycle bin in the target)
- ShortcutCheck - Produce a listing of shortcuts in a folder before exporting it as these are not exported, so users can recreate them if needed.
- ExportCheck - Check an export package for missing components. For example, if an object exists in the package but its containing folder does not (importing this would result in it being placed in the SAS Content root), and confirming all child objects of the folder in the source are present in the package.
- FolderCheck - Check a given folder for member objects that do not exist, as this can cause exports to fail.
- ImportCheck - After import, compare the source and target environments for a given folder for any missing objects.

## Functionality
The script has the following functions. These functions can be used together or separately.
### Primary Functions
1. Export - Supplied a given SAS Content folder, the script will create and download an export package of every child object of that folder. Alternatively if an endpoint is supplied (e.g. /reports/reports), create an export of every n (chunksize) objects returned by that endpoint.
2. Import - Supplied a given file system path, will import all pacakages in that path.
3. UserMigrate - Supplied a Source and Target environment, will check for any SAS Logon Manager users present in the source that are not present in the target, and add them.
4. EmptyRB - Empties the recycle bin of a given user or all users.
### Validation Functions
1. ShortcutCheck - Supplied a given SAS Content path, will produce a list of all shortcut objects that exist in that path.
2. FolderCheck - Supplied a given SAS Content path, will recursively get all members of the folder and perform a HEAD on their URI to confirm they exist. If they do not, optionally delete the membership.
3. ExportCheck - Supplied an export package and optionally a SAS Content path, will validate that the export package has all required components for each exported object, and optionally confirms all objects in the supplied path are present in the export package.
4. ImportCheck - Supplied a SAS Content path, compares the paths between the source and target to confirm all objects present in the source are present in the target.

## Usage
### Main Functions
#### Export
This set of options will create and download an export package for each folder within a supplied content path. After downloading successfully it will remove the package it created. Adding the foldercheck option will not export packages if the folder has inaccessible members. Adding the exportcheck option will check the package after export. If retries is set and the export check fails, it will try again to download the package and check again until it gets a successful export or runs out of attempts.

##### Content Path

`transfer_viya.py --exp [--exportcheck] [--foldercheck] [--shortcutcheck] --src-profile Source --output-path /tmp --content-path /Users [--retries #]`

##### Endpoint

`transfer_viya.py --exp [--exportcheck] --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]`

#### Import
This set of options will attempt to upload and import each JSON file in a supplied import path. If exportcheck is set, it will only upload packages that pass the check.

`transfer_viya.py --imp --import-path "/tmp/Export_2020-08-14_082247" [--exportcheck] --tgt-profile Target`

#### Export and Import
This set of options is the same as the export function but after successfully downloading the package it then uploads and imports it.

##### Content path

`transfer_viya.py --exp [--exportcheck] [--foldercheck] [--shortcutcheck] --imp [--importcheck] --tgt-profile Target --src-profile Source --output-path /tmp --content-path /Users [--retries #]`

##### Endpoint

`transfer_viya.py --exp [--exportcheck] --imp --tgt-profile Target --src-profile Source --output-path /tmp --endpoint /reports/reports [--chunksize #]`

#### User Migration
This set of options will move the SASLogon user registration from the target to the source. This is useful when the import process needs to authenticate as a user who has not yet logged in to the target environment.

`transfer_viya.py --usermigrate --src-profile Source --tgt-profile Target`

#### Empty Recycle Bin
This set of options will empty the recycle bin for all users or a given user in the source environment. This can be helpful in limiting the size of the export of a user's home directory (`/Users/<username>`).

`transfer_viya.py --emptyRB --src-profile Source [--user <username>]`

### Validation Functions
#### Import Check
This set of options instructs the script to confirm child objects in a supplied path in the source environment are present in the target. This confirms an import completed successfully.

`transfer_viya.py --importcheck --content-path /Users/sasdemo --src-profile Source --tgt-profile Target`

#### Export Check
This set of options instructs the script to check a supplied export package for missing parent objects. If a folder ID is supplied, it will also check to see if the package is missing any objects present in the folder.

`transfer_viya.py --exportcheck --export-file /tmp/Users_sasdemo_2020-08-05_150000.json [--folder-id <GUID>] --src-profile Source`

#### Folder Check
This set of options checks the supplied folder for any broken memberships. For example, if a file is listed as being in a folder, it will check to see if the file is present. If not, it can optionally delete the invalid membership.

`transfer_viya.py --foldercheck --content-path /Users/sasdemo --src-profile Source [--delete]`

#### Shortcut Check
This set of options check the supplied folder for all reference-type objects, which are not included in an export.

`transfer_viya.py --shortcutcheck --content-path /Users/sasdemo --src-profile Source`

## Additional Options
The following options can be used to customize the behavior of the script:

- `--authCode` - Use authorization code flow for authentication instead of password/refresh token.
- `--include-dependencies` - Include dependent objects when exporting content (default: false).
- `--exclude-rules` - Exclude rules from being exported (default: false).
- `--mapping-file` - Path to a JSON file containing substitution values for the import.
- `--limit` - Limit the number of export jobs to process (useful for testing).
- `--delete` - Delete broken memberships found during `--foldercheck` (default: false).
- `--timeout` - Timeout in seconds to wait for import or export jobs to complete (default: 600).
- `--wait` - Time in seconds to wait between polling import and export job state (default: 1).
- `--insecure` - Ignore SSL certificate validation errors.
- `--verbose` - Enable verbose output for debugging purposes.
