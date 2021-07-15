#!/usr/bin/perl
#
# This file is part of Koha.
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
use CGI;

use C4::Auth qw( get_template_and_user );
use C4::Context;
use C4::Koha;
use C4::Output qw( output_html_with_http_headers );
use C4::Reports qw( GetDelimiterChoices );
use DateTime;
use Koha::DateUtils qw( dt_from_string output_pref );
use Text::CSV::Encoded;

use Koha::Libraries;
use Koha::ItemTypes;
use Koha::Patron::Categories;

my $input    = CGI->new;
my $dbh      = C4::Context->dbh;

my $do_it    = $input->param('do_it');
my $output   = $input->param("output");
my $basename = $input->param("basename");
my $sep      = $input->param("sep") || C4::Context->preference('CSVDelimiter');
$sep = "\t" if ( $sep =~ /^tab/ );

my $template_file = ( $do_it ? "results" : "params" );
my ($template, $borrowernumber, $cookie) = get_template_and_user({
    template_name => "reports/custom/$template_file.tt",
    query => $input,
    type => "intranet",
    flagsrequired => {reports => '*'},
});

my $branch = $input->param('branch');
$branch = ( C4::Context->only_my_library('IndependentBranchesHideOtherBranchesItems') ? C4::Context->userenv->{branch} : $branch );

$template->param(
    report_file => 'borrowers_messages',
    report_title => 'Patron messages',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_categories',
        input_name => 'categories',
        label => 'Patron Categories',
        op => 'IN',
        select_box => 1,
        select_loop => [ map +{ value => $_->categorycode, label => $_->description }, Koha::Patron::Categories->search_with_library_limits->as_list ],
        first_blank => 1,
        multiple => 1,
    },
);

my @column_titles = ( "Patron", "Cardnumber", "Date", "From", "For", "Message" );

my $query = "";
my @query_params;
my @columns = ( "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron", "cardnumber", "message_date", "messages.branchcode", "IF( message_type = 'B', 'Borrower', 'Librarian' )", "message", "message_id", "borrowernumber" );
my $order = "patron";

my @filters;
my ( $page_breaks, $break_index, $subtotal_index );

if ( $do_it ) {
    foreach my $param ( @parameters ) {
        next unless ( $param->{crit} );

        my $val = $input->param( $param->{input_name} );
        if ( defined $val && ( $val || $val eq '0' ) ) {
            if ( $param->{calendar} ) {
                $val = eval { output_pref({ dt => dt_from_string($val), dateonly => 1, dateformat => 'iso' }); }
            }
            my $set = { crit => $param->{crit}, op => $param->{op}, filter => '?', label => $param->{label}, value => $val };
            unless ( defined $param->{filter} ) {
                push @query_params, $val;
            }
            else {
                $set->{filter} = $param->{filter};
                $set->{value} = $param->{display};
            }

            push @filters, $set;
        }
    }

    if ( $input->param('categories') ) {
        my @cats = $input->multi_param('categories');
        push @filters, { crit => 'borrowers.categorycode', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @cats) .')', label => 'Patron Categories', value => join ',',@cats };
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        if ( C4::Context->preference('AllowAllMessageDeletion') ) {
            push @filters, { crit => 'borrowers.branchcode', op => '=', filter => $dbh->quote($branch), label => 'Patrons at Library', value => $branchname };
        }
        else {
            push @filters, { crit => 'messages.branchcode', op => '=', filter => $dbh->quote($branch), label => 'Messages at Library', value => $branchname };
        }
    }

    $query = "SELECT ". (join ',',@columns) ." FROM messages CROSS JOIN borrowers USING (borrowernumber) ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'WHERE '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, ($output ne 'file') );
    if ( $output eq 'file' ) {
        my $filename = "$basename.csv";
        $filename = "$basename.tsv" if ( $sep =~ m/^\t/ );
        my $csv = Text::CSV::Encoded->new({ encoding_out => 'UTF-8', sep_char => $sep });
        my $content = '';
        $csv->combine(@column_titles);
        $content .= $csv->string() ."\n";
        for my $table ( @$results ) {
            for my $row ( @{ $table->{results} } ) {
                my @out;
                for my $column ( @$row ) {
                    if ( $column->{colspan} ) {
                        push @out, '' for ( 1..($column->{colspan} - 1) );
                    }
                    push @out, $column->{value};
                }
                $csv->combine(@out);
                $content .= $csv->string() ."\n";
            }
            if ( $table->{footer} ) {
                my @out;
                for my $row ( @{ $table->{footer} } ) {
                    for my $column ( @$row ) {
                        if ( $column->{colspan} ) {
                            push @out, '' for ( 1..($column->{colspan} - 1) );
                        }
                        push @out, $column->{value};
                    }
                }
                $csv->combine(@out);
                $content .= $csv->string() ."\n";
            }
        }
        print $input->header(
            -type => 'application/vnd.sun.xml.calc',
            -encoding => 'utf-8',
            -attachment=>"$filename",
            -filename=>"$filename",
            );
        print $content;
    }
    else {
        push @column_titles, 'Action';
        $template->param(
            'headers' => [ map +{ title => $_ }, @column_titles ],
            breakingloop => $results
        );
        output_html_with_http_headers $input, $cookie, $template->output;
    }
}
else {
    # show the parameters form
    output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
    my ( $query, $params, $num_columns, $screen ) = @_;
    my ( @outer, $inner );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];

        $results[0]->{link} = "/cgi-bin/koha/members/moremember.pl?borrowernumber=$values[7]";
        $results[2]->{'is_date','with_hours'} = (1,1);
        if ( $screen ) {
            push @results, {
                value => 'Delete',
                link => "/cgi-bin/koha/circ/del_message.pl?message_id=$values[6]&borrowernumber=$values[7]",
            }
        }

        push @{$inner->{'results'}}, \@results;
    }

    push @outer, $inner;
    return \@outer;
}
