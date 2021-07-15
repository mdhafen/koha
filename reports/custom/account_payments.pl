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
use Koha::Account::DebitTypes;
use Koha::Account::CreditTypes;

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
    report_file => 'account_payments',
    report_title => 'Patron Payments',
    report_desc => '',
    do_it => $do_it,
    CGIsepChoice => GetDelimiterChoices,
);

my @parameters = (
    {
        input_id => 'cr_cal_from',
        input_name => 'cal_from',
        calendar => 1,
        to_id => 'cr_cal_to',
        label => 'Credits added since',
        crit => 'al1.date',
        op => '>=',
    },
    {
        input_id => 'cr_cal_to',
        input_name => 'cal_to',
        calendar => 1,
        label => 'Credits added before',
        crit => 'al1.date',
        op => '<=',
    },
    {
        input_id => 'cr_finetypes',
        input_name => 'fine_types',
        label => 'Fine Types',
        crit => '',  # 'al2.debit_type_code',
        op => '',  # 'IN',
        select_box => 1,
        select_loop => [ map +{ value => $_->code, label => $_->description }, Koha::Account::DebitTypes->search()->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_credittypes',
        input_name => 'credit_types',
        label => 'Credit Types',
        crit => '',  # 'al1.credit_type_code',
        op => '',  # 'IN',
        select_box => 1,
        select_loop => [ map +{ value => $_->code, label => $_->description }, Koha::Account::CreditTypes->search()->as_list ],
        first_blank => 1,
        multiple => 1,
    },
    {
        input_id => 'cr_paymenttypes',
        input_name => 'payment_types',
        label => 'Payment Type',
        crit => '',  #  'al1.payment_type',
        op => '=',
        select_box => 1,
        select_loop => [{value=>'NULL',label=>'Not set'}, map +{ value => $_->authorised_value, label => $_->lib }, grep {$_->lib !~ /via SIP2$/} @{Koha::AuthorisedValues->search_with_library_limits({category=>'PAYMENT_TYPE'},{order_by=>['lib']},$branch)->as_list} ],
        first_blank => 1,
        multiple => 1,
    },
);

my @column_titles = ( "Date", "Patron", "Title", "Barcode", "Amount", "Credit Type", "Credit Description", "Payment Type", "Fine Type", "Fine Description" );

my $query;
my @query_params;
my @columns = ( "al1.date", "CONCAT_WS(', ',borrowers.surname,borrowers.firstname) AS patron", "CONCAT_WS(' ',biblio.title,biblio.subtitle) AS title", "items.barcode", "al1.amount","al1.credit_type_code AS CreditType", "al1.description AS CreditDescription", "COALESCE(av1.lib,'') AS PaymentDescription", "al2.debit_type_code AS FineType", "al2.description AS FineDescription", "al1.borrowernumber" );
my $where = "al1.amount < 0";
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

    my @fines = $input->multi_param('fine_types');
    my @credits = $input->multi_param('credit_types');
    if ( @fines || @credits ) {
        my @all_types = ( @fines, @credits );
        my @where;
        if ( @fines ) {
            push @where, 'al2.debit_type_code IN ('. (join ',', map { $dbh->quote($_) } @fines) .')';
        }
        if ( @credits ) {
            push @where, 'al1.credit_type_code IN ('. (join ',', map { $dbh->quote($_) } @credits) .')';
        }
        push @filters, { crit => '('. (join ' OR ', @where) .')', op => '', filter => '', label => 'Fine/Credit Type', value => join ',',@all_types };
    }

    if ( $input->param('payment_types') ) {
        my $not_set = 0;
        my @pay_types = $input->multi_param('payment_types');
        if ( grep { $_ eq 'NULL' } @pay_types ) {
            @pay_types = grep { $_ ne 'NULL' } @pay_types;
            $not_set = 1;
        }
        my $filt = { crit => 'al1.payment_type', op => 'IN', filter => '('. (join ',', map { $dbh->quote($_) } @pay_types ) .')', label => 'Payment Types', value => join ',',@pay_types };
        if ( $not_set ) {
            $filt->{'crit'} = '( '. $filt->{'crit'};
            $filt->{'filter'} .= ' OR al1.payment_type IS NULL )';
            $filt->{'value'} .= ', Not set';
        }
        push @filters, $filt;
    }

    if ( $branch ) {
        my $library = Koha::Libraries->find($branch);
        my $branchname = $library ? $library->branchname : '';

        push @filters, { crit => 'al1.branchcode', op => '=', filter => $dbh->quote($branch), label => 'Library', value => $branchname };
    }

    $query = "SELECT ". (join ',',@columns) ." FROM accountlines AS al1 LEFT JOIN borrowers USING (borrowernumber) LEFT JOIN items USING (itemnumber) LEFT JOIN biblio USING (biblionumber) LEFT JOIN account_offsets AS ao ON al1.accountlines_id = ao.credit_id AND ao.debit_id IS NOT NULL LEFT JOIN accountlines AS al2 ON ao.debit_id = al2.accountlines_id LEFT JOIN authorised_values AS av1 ON al1.payment_type = av1.authorised_value AND av1.category='PAYMENT_TYPE' WHERE $where";

    my @q_filters = grep { $_->{crit} && defined $_->{filter} } @filters;
    $query .= ' AND '. join( ' AND ', map { "$_->{crit} $_->{op} $_->{filter}" } @q_filters ) ." " if (@q_filters);

    $query .= "ORDER BY $order" if ($order);
}

$template->param(
    'parameters' => \@parameters,
    'filters' => \@filters,
    'headers' => [ map +{ title => $_ }, @column_titles ],
);

if ( $do_it ) {
    my $results = calculate( $query, \@query_params, scalar @column_titles, $page_breaks, $break_index, $subtotal_index );
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
    my ( $query, $params, $num_columns, $page_breaks, $break_index, $subtotal_index ) = @_;
    my ( @outer, $inner, $total, $subtotal, $break, $subtotal_break );
    my $dbh = C4::Context->dbh;
    $inner = {results=>[],footer=>[]};

    my $sth = $dbh->prepare( $query );
    $sth->execute( @$params );
    while ( my ( @values ) = $sth->fetchrow ) {
        my @results = map +{ value => $_ }, @values[0..$num_columns-1];
        $results[0]->{'is_date','with_hours'} = (1,1);
        $results[4]->{value} = sprintf( "%.2f", $values[4] );

        if ( defined $subtotal_index && ( ! defined $subtotal_break || $subtotal_break ne $results[$subtotal_index]->{value} ) ) {
            if ( defined $subtotal_break ) {
                push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
                    {
                        colspan => $num_columns - 1,
                        value => 'Subtotal',
                    },
                    {
                        value => sprintf( "%.2f", $subtotal ),
                    }
                ];
                $subtotal = 0;
            }
            $subtotal_break = $results[$subtotal_index]->{value};
        }

        if ( $page_breaks && ( ! defined $break || $break ne $results[$break_index]->{value} ) ) {
            if ( defined $break ) {
                push @outer, $inner;
                $inner = {results=>[],footer=>[]};
                $inner->{break} = 1;
            }
            $break = $results[$break_index]->{value};
        }

        push @{$inner->{'results'}}, \@results;
        $total += $results[ 4 ]->{value};
        #$subtotal += $results[ $num_columns-1 ]->{value};
    }

    if ( defined $subtotal_index && $inner->{'results'} && @{$inner->{'results'}} ) {
        push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
            {
                colspan => $num_columns - 1,
                value => 'Subtotal',
            },
            {
                value => sprintf( "%.2f", $subtotal ),
            }
        ];
        $subtotal = 0;
    }

    if ( $total ) {
        if ( $page_breaks ) {
            push @outer, $inner;
            $inner = {break=>1,nodata=>1,results=>[]};
        }
        push @{$inner->{ $page_breaks ? 'results' : 'footer' }}, [
            {
                colspan => $num_columns - 1,
                value => 'Total',
            },
            {
                value => sprintf( "%.2f", $total ),
            }
        ]
    }

    push @outer, $inner;
    return \@outer;
}
