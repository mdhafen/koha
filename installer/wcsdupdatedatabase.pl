#!/usr/bin/perl

# Database Updater
# This script checks for required updates to the database.

# Parts copyright Catalyst IT 2011

# Part of the Koha Library Software www.koha-community.org
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.
#

# NOTE: Please keep the version in C4/WCSDVersion.pm up-to-date!

use Modern::Perl;

use feature 'say';

# CPAN modules
use DBI;
use Getopt::Long;
# Koha modules
use C4::Context;
use C4::Installer;
use Koha::Database;
use Koha::DateUtils;
use C4::WCSDVersion;

use MARC::Record;
use MARC::File::XML ( BinaryEncoding => 'utf8' );

use File::Path qw[remove_tree]; # perl core module
use File::Slurp;

# FIXME - The user might be installing a new database, so can't rely
# on /etc/koha.conf anyway.

my $debug = 0;

my (
    $sth,
    $query,
    $table,
    $type,
);

my $schema = Koha::Database->new()->schema();

my $silent;
GetOptions(
    's' =>\$silent
    );
my $dbh = C4::Context->dbh;
$|=1; # flushes output

local $dbh->{RaiseError} = 0;

# Record the version we are coming from

my $original_version = C4::Context->preference("WCSDVersion");
my $DBversion = '0.000';

$DBversion = '5.001';
if( CheckVersion( $DBversion ) ) {
    NewVersion( $DBversion, "", "Adding WCSD Fork of Koha database update support" );
}

#$DBversion = '5.XXX';
#if ( CheckVersion($DBversion) ) {
#    $dbh->do(q{
#    });
#
#    NewVersion( $DBversion, "", "" );
#}

#$DBversion = '26.000';
#if( CheckVersion( $DBversion ) ) {
#    NewVersion( $DBversion, "", "Koha 21.05.00 release" );
#}

=head1 FUNCTIONS

=head2 DropAllForeignKeys($table)

Drop all foreign keys of the table $table

=cut

sub DropAllForeignKeys {
    my ($table) = @_;
    # get the table description
    my $sth = $dbh->prepare("SHOW CREATE TABLE $table");
    $sth->execute;
    my $vsc_structure = $sth->fetchrow;
    # split on CONSTRAINT keyword
    my @fks = split /CONSTRAINT /,$vsc_structure;
    # parse each entry
    foreach (@fks) {
        # isolate what is before FOREIGN KEY, if there is something, it's a foreign key to drop
        $_ = /(.*) FOREIGN KEY.*/;
        my $id = $1;
        if ($id) {
            # we have found 1 foreign, drop it
            $dbh->do("ALTER TABLE $table DROP FOREIGN KEY $id");
            $id="";
        }
    }
}

=head2 SetVersion

set the DBversion in the systempreferences

=cut

sub SetVersion {
    return if $_[0]=~ /XXX$/;
      #you are testing a patch with a db revision; do not change version
    my $kohaversion = $_[0];
    if (C4::Context->preference('WCSDVersion')) {
      my $finish=$dbh->prepare("UPDATE systempreferences SET value=? WHERE variable='WCSDVersion'");
      $finish->execute($kohaversion);
    } else {
      my $finish=$dbh->prepare("INSERT into systempreferences (variable,value,explanation) values ('WCSDVersion',?,'The WCSD version of the database. WARNING: Do not change this value manually, it is maintained by the update script (webinstaller)')");
      $finish->execute($kohaversion);
    }
    C4::Context::clear_syspref_cache(); # invalidate cached preferences
}

sub NewVersion {
    my ( $DBversion, $bug_number, $descriptions ) = @_;

    SetVersion($DBversion);

    unless ( ref($descriptions) ) {
        $descriptions = [ $descriptions ];
    }
    my $first = 1;
    my $time = POSIX::strftime("%H:%M:%S",localtime);
    for my $description ( @$descriptions ) {
        if ( @$descriptions > 1 ) {
            if ( $first ) {
                unless ( $bug_number ) {
                    say sprintf "Upgrade to %s done [%s]: %s", $DBversion, $time, $description;
                } else {
                    say sprintf "Upgrade to %s done [%s]: Bug %5s - %s", $DBversion, $time, $bug_number, $description;
                }
            } else {
                say sprintf "\t\t\t\t\t\t   - %s", $description;
            }
        } else {
            unless ( $bug_number ) {
                say sprintf "Upgrade to %s done [%s]: %s", $DBversion, $time, $description;
            } else {
                say sprintf "Upgrade to %s done [%s]: Bug %5s - %s", $DBversion, $time, $bug_number, $description;
            }
        }
        $first = 0;
    }
}

=head2 CheckVersion

Check whether a given update should be run when passed the proposed version
number. The update will always be run if the proposed version is greater
than the current database version and less than or equal to the version in
kohaversion.pl. The update is also run if the version contains XXX, though
this behavior will be changed following the adoption of non-linear updates
as implemented in bug 7167.

=cut

sub CheckVersion {
    my ($proposed_version) = @_;
    my $version_number = $proposed_version;
    my $pref_version = C4::Context->preference("WCSDVersion") || 0;

    # The following line should be deleted when bug 7167 is pushed
    return 1 if ( $proposed_version =~ m/XXX/ );

    if ( $pref_version < $version_number
        && $version_number <= $WCSDVersion::VERSION )
    {
        return 1;
    }
    else {
        return 0;
    }
}

sub sanitize_zero_date {
    my ( $table_name, $column_name ) = @_;

    my (undef, $datatype) = $dbh->selectrow_array(qq|
        SHOW COLUMNS FROM $table_name WHERE Field = ?|, undef, $column_name);

    if ( $datatype eq 'date' ) {
        $dbh->do(qq|
            UPDATE $table_name
            SET $column_name = NULL
            WHERE CAST($column_name AS CHAR(10)) = '0000-00-00';
        |);
    } else {
        $dbh->do(qq|
            UPDATE $table_name
            SET $column_name = NULL
            WHERE CAST($column_name AS CHAR(19)) = '0000-00-00 00:00:00';
        |);
    }
}

exit;
