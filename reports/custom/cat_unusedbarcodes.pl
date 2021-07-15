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

my $barcode_schema = "T". $branch ."%06d";
my $max_num = 1000000;
my $range = '';
my $limit;

$template->param(
    report_file => 'cat_unusedbarcodes',
    report_title => 'Unused barcodes',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_range',
        input_name => 'range',
        label => 'Show results as',
        first_blank => 0,
        radio_group => 1,
        radio_loop => [{value=>'',label=>'barcode per line'},{value=>'range',label=>'barcode range per line',selected=>1}],
    },
    {
        input_id => 'cr_limit',
        input_name => 'limit',
        label => 'Number of lines with one barcode per line',
        input_box => 1,
        value => 30,
    },
);

my @column_titles = ( "Barcodes" );

my $query = "";
my @query_params;
my @columns = ( "barcode" );
my $where = "barcode <> ''";
my $order = "barcode";
my $group = "";

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

    if ( $input->param('range') ) {
        $range = 1;
    }
    if ( $input->param('limit') ) {
        $limit = 0 + $input->param('limit');
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'items.homebranch', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    $query = "SELECT ". (join ',',@columns) ." FROM items WHERE $where ";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= 'AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "GROUP BY $group " if ($group);
    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, $branch, $barcode_schema, $max_num, $range, $limit );
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
        $template->param(breakingloop => $results);
        output_html_with_http_headers $input, $cookie, $template->output;
    }
}
else {
    # show the parameters form
    output_html_with_http_headers $input, $cookie, $template->output;
}

sub calculate {
    my ( $query, $params, $branch, $barcode_schema, $max_num, $range, $limit ) = @_;
    my ( @outer, $inner, $break );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};
    my %unique = ();
    my @barcodes = ();
    my $lines = 0;

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my $bar = $values[0];
        $bar =~ s/\D+\d?\s*$//;
        $bar =~ /^\s*([\D\s]*(?:$branch)?)(0*)(\d+)$/;
        my $prefix = $1;
        my $padding = $2;
        my $sort = $3;
        $unique{ $sort }++;
    }
    @barcodes = sort { $a <=> $b } keys %unique;
    for ( my $i = 0, my $end = $#barcodes; $i < $end; $i++ ) {
        my $num = $barcodes[$i];
        my ( $first, $last );
        while ( $break && $break < $max_num && ++$break < $num ) {
            $first = $break if ( $range && ! defined $first );
            if ( ! $range && $lines < $limit ) {
                $lines++;
                my $bar = sprintf( $barcode_schema, $break );
                my @results = ( { value => "$bar" } );
                push @{$inner->{'results'}}, \@results;
            }
            $last = $break;
        }
        if ( $range && defined $first && defined $last ) {
            my $value = sprintf( $barcode_schema, $first );
            $value .= ' - ';
            $value .= sprintf( $barcode_schema, $last );
            my @results = ( { value => $value } );
            push @{$inner->{'results'}}, \@results;
        }
        $break = $num;
    }

    if ( $break < $max_num ) {
        if ( $range ) {
            my $value = sprintf( $barcode_schema, $break + 1 );
            $value .= ' - ';
            $value .= sprintf( $barcode_schema, $max_num - 1 );
            my @results = ( { value => $value } );
            push @{$inner->{'results'}}, \@results;
        }
        else {
            while ( ++$break < $max_num && ( ! $limit || $lines < $limit ) ) {
                my $bar = sprintf( $barcode_schema, $break );
                my @results = ( { value => "$bar" } );
                push @{$inner->{'results'}}, \@results;
                $lines++;
            }
        }
    }

    push @outer, $inner;
    return \@outer;
}
