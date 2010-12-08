#!/usr/bin/perl

use strict;
use warnings;

use InstallAuth;
use C4::Context;
use C4::Output;

use CGI;
use IPC::Cmd;

my $query = new CGI;

my ( $template, $loggedinuser, $cookie );
( $template, $loggedinuser, $cookie ) = get_template_and_user(
    {
        template_name => "installer/wcsd_update.tmpl",
        query         => $query,
        type          => "intranet",
        authnotrequired => 0,
    }
);

my $op = $query->param('op');
if ( $op && $op eq 'finished' ) {
    #
    # we have finished, just redirect to mainpage.
    #
    print $query->redirect("/cgi-bin/koha/mainpage.pl");
    exit;
}
elsif ( $op && $op eq 'updatestructure' ) {
    my $cmd = C4::Context->config("intranetdir") . "/installer/wcsdversion.pl run";
    my ($success, $error_code, $full_buf, $stdout_buf, $stderr_buf) = IPC::Cmd::run(command => $cmd, verbose => 0);

    if (@$stdout_buf) {
	$template->param(update_report => [ map { { line => $_ } } split(/\n/, join('', @$stdout_buf)) ] );
	$template->param(has_update_succeeds => 1);
    }
    if (@$stderr_buf) {
	$template->param(update_errors => [ map { { line => $_ } } split(/\n/, join('', @$stderr_buf)) ] );
	$template->param(has_update_errors => 1);
    }

    $template->param( $op => 1 );
}
else {
    if (C4::Context->preference('WCSDVersion')) {
	my $cgidir = C4::Context->config('intranetdir');
	if ( -d $cgidir."/cgi-bin" ) {
	    $cgidir .= "/cgi-bin";
	}
	do $cgidir."/installer/wcsdversion.pl" || die "No $cgidir/installer/wcsdversion.pl";
	my $wcsd_version = wcsd_version();
	my $dbversion = C4::Context->preference('WCSDVersion');
	$dbversion =~ /(.*)\.(..)(..)(...)/;
	$dbversion = "$1.$2.$3.$4";
	$template->param("upgrading" => 1,
			 "dbversion" => $dbversion,
			 "wcsd_version" => $wcsd_version,
	    );
    }
}

output_html_with_http_headers $query, $cookie, $template->output;
