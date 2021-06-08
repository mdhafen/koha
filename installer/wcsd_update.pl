#!/usr/bin/perl

# This file is part of Koha.
#
# Copyright (C) 2021  Michael Hafen
#
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

use Modern::Perl;
use diagnostics;

use C4::InstallAuth qw( get_template_and_user );
use CGI qw ( -utf8 );
use POSIX qw(strftime);

use C4::Context;
use C4::Output qw( output_html_with_http_headers );
use C4::Templates;
use C4::Languages qw(getAllLanguages getTranslatedLanguages);
use C4::Installer;
use C4::Installer::PerlModules;

use C4::WCSDVersion;

use Koha;

my $query = CGI->new;
my $op = $query->param('op') || 'noop';

my $language = $query->param('language');
my ( $template, $loggedinuser, $cookie );

my $all_languages = getAllLanguages();

if ( defined($language) ) {
    C4::Templates::setlanguagecookie( $query, $language, "install.pl?step=1" );
}
( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "installer/wcsd_update.tt",
        query         => $query,
        type          => "intranet",
        debug           => 1,
    }
);

my %info;
$info{'dbname'} = C4::Context->config("database");
$info{'dbms'}   = (
      C4::Context->config("db_scheme")
    ? C4::Context->config("db_scheme")
    : "mysql"
);
$info{'hostname'} = C4::Context->config("hostname");
$info{'port'}     = C4::Context->config("port");
$info{'user'}     = C4::Context->config("user");
$info{'password'} = C4::Context->config("pass");
$info{'tls'} = C4::Context->config("tls");
    if ($info{'tls'} && $info{'tls'} eq 'yes'){
        $info{'ca'} = C4::Context->config('ca');
        $info{'cert'} = C4::Context->config('cert');
        $info{'key'} = C4::Context->config('key');
        $info{'tlsoptions'} = ";mysql_ssl=1;mysql_ssl_client_key=".$info{key}.";mysql_ssl_client_cert=".$info{cert}.";mysql_ssl_ca_file=".$info{ca};
        $info{'tlscmdline'} =  " --ssl-cert ". $info{cert} . " --ssl-key " . $info{key} . " --ssl-ca ".$info{ca}." "
    }

my $dbh = DBI->connect(
    "DBI:$info{dbms}:dbname=$info{dbname};host=$info{hostname}"
      . ( $info{port} ? ";port=$info{port}" : "" )
      . ( $info{tlsoptions} ? $info{tlsoptions} : "" ),
    $info{'user'}, $info{'password'}
);

if ( $op && $op eq 'finished' ) {
    # Remove the HandleError set at the beginning of the installer process
    C4::Context->dbh->disconnect;

    # we have finished, just redirect to mainpage.
    print $query->redirect("/cgi-bin/koha/mainpage.pl");
    exit;
}
elsif ( $op && $op eq 'updatestructure' ) {
    my $now         = POSIX::strftime( "%Y-%m-%dT%H:%M:%S", localtime() );
    my $logdir      = C4::Context->config('logdir');
    my $dbversion   = C4::Context->preference('WCSDVersion') || 0;
    my $kohaversion = WCSDVersion::version();

    my $filename_suffix = join '_', $now, $dbversion, $kohaversion;
    my ( $logfilepath, $logfilepath_errors ) = (
        chk_log( $logdir, "wcsd_update_$filename_suffix" ),
        chk_log( $logdir, "wcsd_update-error_$filename_suffix" )
        );

    my $cmd = C4::Context->config("intranetdir")
        . "/installer/wcsdupdatedatabase.pl >> $logfilepath 2>> $logfilepath_errors";

    system($cmd );

    my $fh;
    open( $fh, "<:encoding(utf-8)", $logfilepath )
        or die "Cannot open log file $logfilepath: $!";
    my @report = <$fh>;
    close $fh;
    if (@report) {
        $template->param( update_report =>
            [ map { { line => $_ =~ s/\t/&emsp;&emsp;/gr } } split( /\n/, join( '', @report ) ) ]
        );
        $template->param( has_update_succeeds => 1 );
    }
    else {
        eval { `rm $logfilepath` };
    }
    open( $fh, "<:encoding(utf-8)", $logfilepath_errors )
        or die "Cannot open log file $logfilepath_errors: $!";
    @report = <$fh>;
    close $fh;
    if (@report) {
        $template->param( update_errors =>
            [ map { { line => $_ } } split( /\n/, join( '', @report ) ) ]
        );
        $template->param( has_update_errors => 1 );
        warn
"The following errors were returned while attempting to run the wcsd_update.pl script:\n";
        foreach my $line (@report) { warn "$line\n"; }
    }
    else {
        eval { `rm $logfilepath_errors` };
    }
    $template->param( $op => 1 );
}
else {
    $template->param( "default" => 1 );

    my $dbversion = C4::Context->preference('WCSDVersion');
    $template->param(
        "dbversion"   => $dbversion,
        "kohaversion" => WCSDVersion::version(),
        );
}

output_html_with_http_headers $query, $cookie, $template->output;

sub chk_log {    #returns a logfile in $dir or - if that failed - in temp dir
    my ( $dir, $name ) = @_;
    my $fn = $dir . '/' . $name . '.log';
    if ( !open my $fh, '>', $fn ) {
        $name .= '_XXXX';
        require File::Temp;
        ( $fh, $fn ) =
          File::Temp::tempfile( $name, TMPDIR => 1, SUFFIX => '.log' );

        #if this should not work, let croak take over
    }
    return $fn;
}
