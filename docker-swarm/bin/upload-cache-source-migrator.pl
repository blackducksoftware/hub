#!/usr/bin/env perl
#
# Copyright (C) 2023 Black Duck Software, Inc.
# https://www.blackduck.com/
# All rights reserved.
#
# This software is the confidential and proprietary information of
# Black Duck ("Confidential Information"). You shall not disclose such
# Confidential Information and shall use it only in accordance with
# the terms of the license agreement you entered into with Black Duck.

# Migrate sources from pre-2024.1.0 upload-cache storage volumes to a
# 2024.1.0 or later server.  Note that uploaded source is still
# subject to both the DATA_RETENTION_IN_DAYS and aggregate
# MAX_TOTAL_SOURCE_SIZE_MB limits, and may disappear unpredictably.
# Scans will re-upload sources, so you might not find migrating old
# sources worth the effort.

# You will need the following:
#  * A system with Perl 5 installed.  (OpenSSL and derivatives
#    explicitly forbid command line use of GCM ciphers, so this could
#    not be written as a shell script.)
#  * Access to a Black Duck server that has ENABLE_SOURCE_UPLOADS=true
#  * A copy of the 32-byte upload-cache seal key, stored in a file.
#  * Read access to the old upload-cache keys and data volumes.

# Installation / usage
# --------------------
# If you get an error message similar to this:
#   Can't locate JSON/PP.pm in @INC (you may need to install the JSON::PP module) ...
# try to install the missing module (JSON::PP in this example) with either:
#   cpanm JSON::PP
# or the system package manager, e.g. yum install perl-JSON-PP.
# Repeat until all modules are available.  If you have trouble see
# https://www.cpan.org/modules/INSTALL.html (hint: "cpan App::cpanminus")

use strict;
use warnings;
use English;

use Crypt::AuthEnc::GCM qw(gcm_decrypt_verify);
use Crypt::Digest::SHA1 qw(sha1_hex);
use Crypt::Digest::SHA256 qw(sha256);
use Getopt::Long;
use HTTP::Request::Common;
use JSON qw(decode_json);
use LWP::Protocol::https;  # You can --force installation if the 'X509_get_version' test fails; we don't use that.
use LWP::UserAgent;

$OUTPUT_AUTOFLUSH=1;

chomp(my $prog = `basename $0`);

my $BEARER_TOKEN;
my $TOKEN_EXPIRATION=0;

# Parse the command line
my $verbose = 0;
my $continue = 0;
my $help = 0;
my $dry_run = 0;
my $insecure = 0;
my $URL = $ENV{'URL'} || 'https://localhost';
my $API_TOKEN = $ENV{'API_TOKEN'} || '';
my $SEAL_KEY_PATH = $ENV{'SEAL_KEY_PATH'} || '';
my $KEYS_VOLUME = $ENV{'KEYS_VOLUME'} || '';
my $DATA_VOLUME = $ENV{'DATA_VOLUME'} || '';
GetOptions('url=s' => \$URL,
           'api-token=s' => \$API_TOKEN,
           'seal-key-path=s' => \$SEAL_KEY_PATH,
           'keys-volume=s' => \$KEYS_VOLUME,
           'data-volume=s' => \$DATA_VOLUME,
           'continue' => \$continue,
           'verbose|v+' => \$verbose,
           'dry-run|n' => \$dry_run,
           'insecure|k' => \$insecure,
           'help|?' => \$help) or &usage;
&usage if ($help);
&usage("Unknown arguments: @ARGV") if (@ARGV > 0);
&usage("Missing arguments") unless ($URL ne '') && ($API_TOKEN ne '') && ($SEAL_KEY_PATH ne '') && ($KEYS_VOLUME ne '') && ($DATA_VOLUME ne '');

# Validate key configuration
print "... Decrypting master key\n" if ($verbose > 0);
my $masterKey = &get_master_key($SEAL_KEY_PATH, $KEYS_VOLUME);

# Validate network connectivity
my $ua = LWP::UserAgent->new;
if ($insecure) {
    print "... Trusting all SSL certificates\n" if ($verbose > 0);
    $ua->ssl_opts(
        SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE,
        verify_hostname => 0
    );
}
print "... Verifying connectivity to $URL\n" if ($verbose > 0);
&refresh_bearer_token;

# Process files
print "... Processing files in $DATA_VOLUME/sources\n" if ($verbose > 0);
my $filenum = 0;
my @files = glob("$DATA_VOLUME/sources/*/*");
foreach my $file (@files) {
    $filenum ++;
    if ($file =~ m:/[a-f0-9]{40}$:) {
        print "... $file ($filenum of ${\scalar(@files)})\n" if ($verbose > 0);
        eval { &process_file($file) };
        if ($@) { if ($continue) { warn $@ } else { die $@ } };
    }
}

# Done!
exit 0;

# --------------------------------------------------------------------------------

# Print usage and exit
sub usage {
    # Output any supplied messages
    print STDERR join("\n", @_), "\n" if (@_);

    print <<EOT ;
usage: $prog [ --option ]*
Valid options are:
    --url <url>             Base URL for the Black Duck server [$URL]
    --api-token <string>    A Black Duck API token [@{[length($API_TOKEN) ? '(redacted)' : '']}]
    --seal-key-path <path>  Location of a file containing the seal key [$SEAL_KEY_PATH]
    --keys-volume <path>    Location of the upload-cache keys volume [$KEYS_VOLUME]
    --data-volume <path>    Location of the upload-cache data volume [$DATA_VOLUME]
    --insecure | -k         Skip SSL certificate verification
    --continue              Continue processing files after an error
    --dry-run | -n          Do everything except upload data
    --verbose | -v          Print more output, repeatable

Values can be supplied on the command line via options or via environment variables
(URL, API_TOKEN, SEAL_KEY_PATH, KEYS_VOLUME, or DATA_VOLUME).

Source files will be extracted from the data volume and uploaded to the Black Duck
server.
EOT
    exit 1;
}

# Load and return the master key
sub get_master_key {
    my ($sealKeyPath, $keysVolumePath) = @_;

    # Read the raw data
    my $sealKey = &get_bytes($sealKeyPath, 32);
    my $masterKeyEncrypted = &get_bytes("$keysVolumePath/MASTER_KEY_ENCRYPTED", 60);
    my $masterKeyHashed = &get_bytes("$keysVolumePath/MASTER_KEY_HASHED", 32);

    # Decrypt and verify the master key.
    my $result = &decrypt("$keysVolumePath/MASTER_KEY_ENCRYPTED", $sealKey, $masterKeyEncrypted);
    die "*** Invalid seal key" unless (sha256($result) eq $masterKeyHashed);

    return $result;
}

# Read a binary file and return the contents as a string.
sub get_bytes {
    my ($path, $requiredLength) = @_;

    # Read the data into a string.
    print ".. Reading '$path'\n" if ($verbose > 1);
    open(HANDLE, '<:raw', $path) || die "*** Could not read $path: $!\n";
    my $result = do { local $/; <HANDLE> };
    close(HANDLE) || die "*** Could not close $path after reading: $!\n";

    # Check length requirements
    if (defined($requiredLength) && ($requiredLength >= 0)) {
        my $actualLength = length($result);
        die "*** $path is too short; $requiredLength bytes are required but only $actualLength exist" if ($actualLength < $requiredLength);
        if ($actualLength == $requiredLength + 1) { chomp($result); $actualLength = length($result) }
        die "*** $path is too long; $requiredLength bytes are required but $actualLength exist" unless ($actualLength == $requiredLength);
    }

    return $result;
}

# Decrypt data or die trying. Return the clear text.
sub decrypt {
    my ($source, $key, $rawData) = @_;

    my $nonce = substr($rawData, 0, 12);
    my $cipherText = substr($rawData, 12, -16);
    my $tag = substr($rawData, -16);
    my $result = gcm_decrypt_verify('AES', $key, $nonce, undef, $cipherText, $tag) || die "*** unable to decrypt $source\n";
    return $result;
}

# Obtain a bearer token from the Black Duck server or die, setting global
# BEARER_TOKEN and TOKEN_EXPIRATION variables.
sub refresh_bearer_token {
    my $now = time;
    if ($TOKEN_EXPIRATION < $now + 120) {
        print ".. fetching a new bearer token\n" if ($verbose > 1);
        my $response = $ua->request(POST "$URL/api/tokens/authenticate", Authorization => "token $API_TOKEN");
        die "*** Unable to authenticate API token: @{[$response->status_line]}\n" unless $response->is_success;

        my $jsonRef = decode_json($response->content);
        $TOKEN_EXPIRATION = $now + ($jsonRef->{'expiresInMilliseconds'} / 1000);
        $BEARER_TOKEN = $jsonRef->{'bearerToken'};
        die "*** Malformed response" if ($TOKEN_EXPIRATION < $now + 120);
    }
}

# Upload source to Black Duck.  The file name should end with the sha1sum of the content.
sub upload_source {
    my ($file, $data) = @_;
    my $checksum = (split '/', $file)[-1];

    # Verify that we decrypted the file correctly
    my $actualChecksum = sha1_hex($data);
    die "*** Checksum mismatch decrypting $file: got $actualChecksum\n" unless $checksum eq $actualChecksum;

    # Make sure the bearer token is still valid
    &refresh_bearer_token;

    # Upload the data.  Likely results:
    #  "405 Not Allowed" means ENABLE_SOURCE_UPLOADS is not set on the server
    return if ($dry_run);
    my $response = $ua->request(PUT "$URL/api/scan-sources/$actualChecksum",
                                Authorization    => "Bearer $BEARER_TOKEN",
                                'Content-Length' => length($data),
                                'Content-Type'   => "application/octet-stream",
                                Content          => $data);
    die "*** Unable to upload $file: @{[ $response->status_line ]}\n" unless $response->is_success;
}

# Process a single file
sub process_file {
    my ($file) = @_;

    my $rawData = &get_bytes($file);
    my $text = &decrypt($file, $masterKey, $rawData);
    &upload_source($file, $text);  
}
