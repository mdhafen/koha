
# -*- tab-width: 4 -*-
# NOTE: This file uses 4-character tabs; do not change the tab size!

package C4::Members;

# Copyright 2008 Michael Hafen
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 2 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# Koha; if not, write to the Free Software Foundation, Inc., 59 Temple Place,
# Suite 330, Boston, MA  02111-1307 USA


use strict;
use warnings;
use vars qw( %MembersExternal_Context );
use Digest::MD5 qw(md5_base64);
use C4::Context;

our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,$debug);

BEGIN {
    $VERSION = 2.00;
    $debug = $ENV{DEBUG} || 0;
    require Exporter;
    @ISA = qw(Exporter);
    #Get data
    push @EXPORT, qw(
	&GetMemberDetails_External
	&GetMemberColumns_External
	&ListMembers_External
	&GetExternalMappedCategories
	);

    #Modify data
    push @EXPORT, qw(
	&ModMember_External
	);

    #Delete data
    push @EXPORT, qw(
	&DelMember_External
	);

    #Insert data
    push @EXPORT, qw(
	&AddMember_External
	);

    #Check data
    push @EXPORT, qw(
	&checkpw_external
	&Check_Userid_External
	);

    # Private subs
    #Get data
    push @EXPORT_OK, qw(
	&GetMemberCardnumber
	&GetExternalField
	&GetExternalAttrib
	&GetExternalAllAttribs
	&GetMemberDetails_LDAP
	&GetMemberDetails_DBI
	&GetMemberColumns_LDAP
	&GetMemberColumns_DBI
	&ListMembers_LDAP
	&ListMembers_DBI
	);

    #Modify data
    push @EXPORT_OK, qw(
	&ModMember_LDAP
	&ModMember_DBI
	);

    #Delete data
    push @EXPORT_OK, qw(
	&DelMember_LDAP
	&DelMember_DBI
	);

    #Insert data
    push @EXPORT_OK, qw(
	&AddMember_LDAP
	&AddMember_DBI
	);

    #Check data
    push @EXPORT_OK, qw(
	&PatronInMappedCategory
	&Check_Userid_LDAP
	&Check_Userid_DBI
	&checkpw_LDAP
	&checkpw_DBI
	);

    #Connection handling
    push @EXPORT_OK, qw(
	&LDAP_connect
	&LDAP_search
	&LDAP_add
	&LDAP_modify

	&DBI_BuildQuery
	);
}

%MembersExternal_Context = (
    conn => undef,  # DBI handle or LDAP connection
    bind => undef,  # LDAP bind
    engine => C4::Context->config('MembersExternalEngine'),
    pass_method => C4::Context->config('MembersExternalPassMethod'),
    host => C4::Context->config('MembersExternalHost'),
    user => C4::Context->config('MembersExternalUser'),
    pass => C4::Context->config('MembersExternalPass'),
    schema => C4::Context->config('MembersExternalSchema'),
    DNfield => C4::Context->config('MembersExternalDNField'),
    );

=head1 NAME

C4::MembersExternal - Perl Module extending C4::Members to allow getting member information from sources other than the Koha database

=head1 SYNOPSIS

use C4::MembersExternal;

=head1 DESCRIPTION

This module contains routines for adding, modifying and deleting members/patrons/borrowers where the information for those members/patrons/borrowers is held in a source other than the Koha database

=head1 VARIABLES

There are a few configuration variable to handle.  First is the method, which is either 'ldap' or a dbi driver.  Second is how the passwords are stored, either 'plain' or 'md5'.  Third the host, username, and password with access to the directory or database.  Also, if you are using ldap, the base DN is needed.  And the DN field: OpenLDAP dn is dn, ActiveDirectory dn is distinguishedName.

=head1 FUNCTIONS

=over 2

=item GetMemberDetails_External

  $borrower = &GetMemberDetails_External($cardnumber);

Returns information on a patron (borrower) by card number.

C<$borrower> is a reference-to-hash with keys from the C<borrowers> table of the Koha database for columns that have been mapped to an external database or directory.

This function routes the the appropriate LDAP or DBI function to do the actual work.

=cut

#'
sub GetMemberDetails_External {
    my ( $cardnumber, $category ) = @_;
    my ( $data );

    return $data unless ( $category = PatronInMappedCategory( undef, $cardnumber, $category ) );

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	$data = GetMemberDetails_LDAP( $cardnumber, $category );
    } else {
	$data = GetMemberDetails_DBI( $cardnumber, $category );
    }

    return $data;
}

=item GetMemberColumns_External
  $columns = &GetMemberColumns_External( \@columns );

For all C<@columns> that are mapped this sub will return a hash-ref of array-refs where the hash-ref keys are column names, and the array-refs contain all the values in the Koha and External databases for those columns.  This is a short-cut sub to make building select lists in the templates much easier.  Also could be useful in an authority or value_builder.

The extra step is taken for each column to make sure that only one value is returned for any patrons that are mapped to the External database.  This is to eliminate phantom values where the Koha database is out of sync with the External database.

=cut

sub GetMemberColumns_External {
    my ( $columns, $branch ) = @_;
    my ( $data );

    $data = {};  # start with the values from the Koha database
    my $dbh = C4::Context->dbh;
    my $query = "SELECT cardnumber,". join ',', @$columns;
    $query .= " FROM borrowers";
    $query .= " WHERE branchcode = ". $dbh->quote( $branch ) if ( $branch );
    my $sth = $dbh->prepare( $query );
    $sth->execute;
    while ( my $result = $sth->fetchrow_hashref ) {
	my $cardnumber = $$result{ cardnumber };
	delete $$result{ cardnumber };
	$$data{ $cardnumber } = $result;
    }

    # Now add/overwrite with external values
    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	$data = GetMemberColumns_LDAP( $columns, $branch, $data );
    } else {
	$data = GetMemberColumns_DBI( $columns, $branch, $data );
    }

    return $data;
}

=item ListMembers_External
  ( $Koha, $External ) = &ListMembers_External( $category, $branch );

Creates two lists: C<Koha> and C<External> which list all the users in the Koha database and the External database for a given patron C<category>.  This is used by the syncronize script to make sure the Koha database is in sync with the External database for a few key fields.  Specifically the script checks the name fields, and branchcode.

=cut

sub ListMembers_External {
    my ( $category, $branch ) = @_;
    my ( %koha, $external );

    my $dbh = C4::Context->dbh;
    my $query = "SELECT borrowernumber,cardnumber,branchcode,surname,firstname,othernames,categorycode FROM borrowers";
    $query .= " WHERE branchcode = ". $dbh->quote( $branch ) if ( $branch );
    my $sth = $dbh->prepare( $query );
    $sth->execute();
    while ( my $data = $sth->fetchrow_hashref ) {
	$koha{ $$data{cardnumber} } = $data;
    }

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	$external = ListMembers_LDAP( $category, $branch );
    } else {
	$external = ListMembers_DBI( $category, $branch );
    }

    return ( \%koha, $external );
}

=item ModMember_External
  $data = &ModMember_External( $data );

Routes to the appropriate LDAP or DBI function to modify patron information.  C<$borrower> is a reference-to-hash with keys from the C<borrowers> table.  For these keys any that are mapped columns will be updated in the external database.

=cut

sub ModMember_External {
    my ( $data ) = @_;
    my $category;

    return $data unless ( $category = PatronInMappedCategory( $$data{'borrowernumber'} ) );

    if ( $MembersExternal_Context{'pass_method'} eq 'md5' ) {
        $$data{'password'} = md5_base64( $$data{'password'} );
    }

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	$data = ModMember_LDAP( $data, $category );
    } else {
	$data = ModMember_DBI( $data, $category );
    }

    return $data;
}

=item DelMember_External
  &DelMember_External( $borrowernumber );

Routes to the appropriate LDAP or DBI function to delete patrons from an external data source.

=cut

sub DelMember_External {
    my ( $BorNum ) = @_;

    return unless ( PatronInMappedCategory( $BorNum ) );

    my $CardNum = GetMemberCardnumber( $BorNum );

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	DelMember_LDAP( $CardNum );
    } else {
	DelMember_DBI( $CardNum );
    }
}

=item AddMember_External
  &AddMember_External( $data );

Routes to the appropriate LDAP or DBI function to add a patron to an external information source.  C<$data> is a reference-to-hash with keys from the C<borrowers> table.  For these keys any that have mapped columns will be added to a new record in the external database.

=cut

sub AddMember_External {
    my ( $data ) = @_;
    my $category;

    return unless ( $category = PatronInMappedCategory( undef, $$data{'cardnumber'} ) );

    if ( $MembersExternal_Context{'pass_method'} eq 'md5' && $$data{'password'} ) {
        $$data{'password'} = md5_base64( $$data{'password'} );
    }

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	AddMember_LDAP( $data, $category );
    } else {
	AddMember_DBI( $data, $category );
    }
}

=item Check_Userid_External
  &Check_Userid_External( $data );

Routes to the appropriate LDAP or DBI function to make sure the supplied userid is unique in the Koha database and the external data source.

=cut

sub Check_Userid_External {
    my ( $userid, $borrnum ) = @_;
    my ( $category, $result );

    $category = PatronInMappedCategory( $borrnum );
    $result = GetExternalAttrib( 'userid', $category );
    if ( $category && $result ) {  # we can do this
	if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	    $result = Check_Userid_LDAP( $userid, $borrnum, $category );
	} else {
	    $result = Check_Userid_DBI( $userid, $borrnum, $category );
	}
    } else {  # fall back to what Members.pm does
	my $dbh = C4::Context->dbh;
	my $sth =
	    $dbh->prepare(
		"SELECT * FROM borrowers WHERE userid=? AND borrowernumber != ?");
	$sth->execute( $userid, $borrnum );
	if ( ( $userid ne '' ) && ( my $row = $sth->fetchrow_hashref ) ) {
	    $result = 0;
	} else {
	    $result = 1;
	}
    }

    return $result;
}

=item &checkpw_external
  ( $retval, $info ) = &checkpw_external( $dbh, $userid, $password );

Checks that C<userid> is a mapped field.  If it is this will hand off the the appropriate lower level sub to check the password and gather information.

=cut

sub checkpw_external {
    my ( $dbh, $userid, $password ) = @_;
    my ( $categorys, $retval, $result );

    my $query = "SELECT attrib,categorycode FROM borrowers_external_structure WHERE kohafield = 'userid'";
    my $sth = $dbh->prepare( $query );
    $sth->execute;
    unless ( $sth->rows ) {  # userid isn't mapped
	return ( 0, undef );
    }
    while ( my ( $attrib, $category ) = $sth->fetchrow ) {
	$$categorys{ $category } = $attrib;
    }

    if ( $MembersExternal_Context{'pass_method'} eq 'md5' ) {
        $password = md5_base64( $password );
    }

    if ( $MembersExternal_Context{'engine'} eq 'ldap' ) {
	$result = checkpw_LDAP( $userid, $password, $categorys );
    } else {
	$result = checkpw_DBI( $userid, $password, $categorys );
    }

    if ( $result ) {
	$retval = 1;
    }
    return ( $retval, $result );
}

=item &GetMemberCardnumber
  $cardnumber = &GetMemberCardnumber( $borrowernumber );

Gets a patron's C<cardnumber> from their C<borrowernumber>.  Cardnumber is used to link a patron in the Koha database to a record in the external database.

=cut

sub GetMemberCardnumber {
    my ( $borrnum ) = @_;
    my $dbh = C4::Context->dbh;
    my $result;

    my $sth = $dbh->prepare( "SELECT cardnumber FROM borrowers WHERE borrowernumber = ?" );
    $sth->execute( $borrnum );

    ( $result ) = $sth->fetchrow;

    return $result;
}

=item PatronInMappedCategory
  $category = &PatronInMappedCategory( $borrowernumber, $cardnumber );

Checkes the C<borrowers_external_structure> table to see if there is a mapping set for the patrons patron category.  Uses either C<borrowernumber> or C<cardnumber>.  Returns the patrons C<category> or undef.

=cut

sub PatronInMappedCategory {
    my ( $borrnum, $cardnum, $cat ) = @_;
    my $dbh = C4::Context->dbh;
    my $sth;
    my @inputs;
    my $result;

    my $query = "SELECT categorycode FROM borrowers WHERE ";
    if ( $cat ) {
	$result = $cat;
    } elsif ( $borrnum ) {
	$query .= "borrowernumber = ?";
	push @inputs, $borrnum;
    } elsif ( $cardnum ) {
	$query .= "cardnumber = ?";
	push @inputs, $cardnum;
    } else {
	warn "PatronInMappedCategory() couldn't find members categorycode without cardnumber or borrowernumber" if $debug;
	return undef;
    }

    unless ( $cat ) {
	$sth = $dbh->prepare( $query );
	$sth->execute( @inputs );
	( $result ) = $sth->fetchrow;
    }

    my @mapped_cats_ar = GetExternalMappedCategories();
    my %mapped_cats = map { $_ => 1 } @mapped_cats_ar;

    $result = ( $mapped_cats{ $result } ) ? $result : undef;

    return $result;
}

=item &GetExternalField
  $column = &GetExternalField( $field, $category );

handles the convertion of a directory or database attribute back to the Koha field.

=cut

sub GetExternalField {
    my ( $field, $category ) = @_;
    my $column;
    my $dbh = C4::Context->dbh;
    my $query = "SELECT kohafield FROM borrowers_external_structure WHERE attrib LIKE ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );
    $sth->execute( "\%$field" );  # watch out for column aliases

    unless ( $sth->rows ) {  # No?  Then check default categorycode
	$sth->finish;
	$query = "SELECT kohafield FROM borrowers_external_structure WHERE attrib LIKE ? AND ( categorycode = '' OR categorycode IS NULL )";
	$sth = $dbh->prepare( $query );
	$sth->execute( "\%$field" );
    }

    ( $column ) = $sth->fetchrow;
    $sth->finish;

    return $column;
}

=item &GetExternalAttrib
  $column = &GetExternalAttrib( $field, $category );

handles the convertion of a Koha field to the database field or directory attribute

=cut

sub GetExternalAttrib {
    my ( $field, $category ) = @_;
    my $column;
    my $dbh = C4::Context->dbh;
    my $query = "SELECT attrib FROM borrowers_external_structure WHERE kohafield = ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );
    $sth->execute( $field );

    unless ( $sth->rows ) {  # No?  Then check default categorycode
	$sth->finish;
	$query = "SELECT attrib FROM borrowers_external_structure WHERE kohafield = ? AND ( categorycode = '' OR categorycode IS NULL )";
	$sth = $dbh->prepare( $query );
	$sth->execute( $field );
    }

    ( $column ) = $sth->fetchrow;
    $sth->finish;

    return $column;
}

=item &GetExternalAllAttribs
  $columns = &GetExternalAllAttribs( $category );

Grabs all the Koha fields that are mapped for C<$category>.  Returns an array-ref.

=cut

sub GetExternalAllAttribs {
    my ( $category ) = @_;
    my %columns;
    my $dbh = C4::Context->dbh;
    my $query;

    # start with the default fields
    $query = "SELECT kohafield,attrib FROM borrowers_external_structure WHERE categorycode = '' OR categorycode IS NULL";
    my $sth = $dbh->prepare( $query );
    $sth->execute();
    while ( $_ = $sth->fetchrow_arrayref ) {
	$columns{ $$_[0] } = $$_[1];
    }
    $sth->finish;

    #  Next the specific mappings for this category
    $query = "SELECT kohafield,attrib FROM borrowers_external_structure WHERE categorycode = ?";
    $sth = $dbh->prepare( $query );
    $sth->execute( $category );
    while ( $_ = $sth->fetchrow_arrayref ) {
	$columns{ $$_[0] } = $$_[1];
    }
    $sth->finish;

    return values %columns;
}

=item &GetExternalMappedCategories

=cut

sub GetExternalMappedCategories {
    my ( @all_cats );

    my $dbh = C4::Context->dbh;
    my $query = "SELECT categorycode FROM borrowers_external_structure GROUP BY categorycode";
    my $sth = $dbh->prepare( $query );
    $sth->execute;
    unless ( $sth->rows == 0 ) {
	while ( my ( $cat ) = $sth->fetchrow ) {
	    push @all_cats, $cat if ( $cat ne '' );
	}
    }
    $sth->finish;

    return @all_cats;
}

=item &GetMemberDetails_DBI

=cut

sub GetMemberDetails_DBI {
    my ( $cardnumber, $category ) = @_;
    my ( @columns, %filter, $query, $sth );
    my ( $data, $result );

    @columns = GetExternalAllAttribs( $category );
    my $filter_field = GetExternalAttrib( 'cardnumber', $category );
    $filter{ $filter_field } = $cardnumber;
    $query = DBI_BuildQuery( $category, \@columns, \%filter );
    return {} unless ( defined $query );
    $sth = $MembersExternal_Context{ conn }->prepare( $query );
    $sth->execute;
    $data = $sth->fetchrow_hashref;

    foreach my $attrib ( keys %$data ) {
	my $field = GetExternalField( $attrib, $category );
	$$result{ $field } = $$data{ $attrib };
    }

    return $result;
}

=item &GetMemberColumns_DBI

=cut

sub GetMemberColumns_DBI {
    my ( $columns, $branch, $data ) = @_;
    my ( %attribs, @all_cats );

    @all_cats = GetExternalMappedCategories();

    unless ( @all_cats ) {
	warn "GetMemberColumns called but no patron categories mapped" if $debug;
	return $data;
    }

    foreach my $cat ( @all_cats ) {
	foreach my $col ( @$columns ) {
	    my $attr = GetExternalAttrib( $col, $cat );
	    if ( $attr ) {
		$attr =~ /^[^\.]*\.?(\S+)/;
		my $short_attr = $1;
		$attribs{ $cat }{ $attr } = $col;
		$attribs{ $cat }{ $short_attr } = $col;
	    }
	}
    }

    foreach my $cat ( keys %attribs ) {
	my $branch_attr = GetExternalAttrib( 'branchcode', $cat );
	my $cardno_attr = GetExternalAttrib( 'cardnumber', $cat );
	my %filter;
	my @columns = keys %{ $attribs{ $cat } };
	$filter{ $branch_attr } = $branch if ( $branch );

	my $query = DBI_BuildQuery( $cat, [ @columns, $cardno_attr ], \%filter );
	next unless ( defined $query );
	my $sth = $MembersExternal_Context{ conn }->prepare( $query );
	$sth->execute;
	while ( my $patron = $sth->fetchrow_hashref ) {
	    my $cardnumber = $$patron{ $cardno_attr };
	    foreach ( keys %$patron ) {
		my $field = $attribs{ $cat }{ $_ };
		$$data{ $cardnumber }{ $field } = $$patron{ $_ } if ( $field );
	    }
	}
    }

    %attribs = ();
    foreach my $patron ( values %$data ) {  # simulate `select distinct` here
	foreach ( keys %$patron ) {
	    $attribs{ $_ }{ $$patron{ $_ } } = 1;
	}
    }
    foreach ( keys %attribs ) {
	$attribs{ $_ } = [ keys %{ $attribs{ $_ } } ];
    }

    return \%attribs;
}

=item &ListMembers_DBI

=cut

sub ListMembers_DBI {
    my ( $category, $branch ) = @_;
    my ( $query, %filter, %list );

    my $cardfield = GetExternalAttrib( 'cardnumber', $category );
    if ( $branch ) {
	my $branchfield = GetExternalAttrib( 'branchcode', $category );
	$filter{ $branchfield } = $branch;
    }

    $query = DBI_BuildQuery( $category, [ $cardfield ], \%filter );
    return {} unless ( defined $query );
    my $sth = $MembersExternal_Context{ conn }->prepare( $query );
    $sth->execute;
    while ( my ( $card ) = $sth->fetchrow ) {
	$list{ $card } = 1;
    }

    return \%list;
}

=item &ModMember_DBI

I admit that I'm lazy.  I am not going to allow any modif's to my external database, so I have no reason to fill in these three functions, or the corresponding LDAP ones.  Someone should do that, and it probably won't be me.

=cut

sub ModMember_DBI {
}

=item &DelMember_DBI

=cut

sub DelMember_DBI {
}

=item &AddMember_DBI

=cut

sub AddMember_DBI {
}

=item &Check_Userid_DBI

=cut

sub Check_Userid_DBI {
    my ( $userid, $borrnum, $category ) = @_;
    my ( %filter, $query );

    my $card = GetMemberCardnumber( $borrnum );
    my $cardfield = GetExternalAttrib( 'cardnumber', $category );
    my $userfield = GetExternalAttrib( 'userid', $category );
    $filter{ $userfield } = $userid;
    $query = DBI_BuildQuery( $category, [ $cardfield ], \%filter );
    return 1 unless ( defined $query );
    my $sth = $MembersExternal_Context{ conn }->prepare( $query );
    $sth->execute;
    if ( $sth->rows ) {
	while ( my ( $found ) = $sth->fetchrow ) {
	    if ( $found ne $card ) {
		return 0;
	    }
	}
    }

    return 1;
}

=item &checkpw_DBI

=cut

sub checkpw_DBI {
    my ( $userid, $password, $categories ) = @_;
    my ( $info, $filter, $cardfield, $passwd_field, $query, $sth, $foundcat );

    foreach my $cat ( keys %$categories ) {
	$filter = { $$categories{ $cat } => $userid };
	$cardfield = GetExternalAttrib( 'cardnumber', $cat );
	$passwd_field = GetExternalAttrib( 'password', $cat );
	$query = DBI_BuildQuery( $cat, [ $cardfield, $passwd_field ], $filter );
	return 0 unless ( defined $query );
	$sth = $MembersExternal_Context{ conn }->prepare( $query );
	$sth->execute;
	#  Check for uniqueness
	if ( $sth->rows > 1 ) {
	    $debug && warn "MembersExternal Auth: got more than one userid match in external database for this category";
	    return;
	}
	if ( $foundcat && $sth->rows ) {
	    $debug && warn "MembersExternal Auth: got more than one userid match across all categories for external database";
	    return;
	}
	if ( $sth->rows ) {
	    $foundcat = $cat;
	    my $data = $sth->fetchrow_hashref;
	    $passwd_field =~ s/.*?([^\.\s]+)$/$1/;
	    $cardfield =~ s/.*?([^\.\s]+)$/$1/;
	    if ( $$data{ $passwd_field } eq $password ) {
		$info = $$data{ $cardfield };
	    }
	}
    }

    return $info;
}

=item &DBI_BuildQuery

Makes sure there's a connection to the database and builds the query to get the requested information.

=cut

sub DBI_BuildQuery {
    my ( $category, $columns, $filters ) = @_;
    my ( $query, $query2 );
    my ( @l_columns, %tables, %weight, $first_table );

    unless ( $MembersExternal_Context{ conn } ) {
	# Connect to the external db
	# this DSN format is required for the sybase driver.
	# Also, Sybase when connecting to mssql doesn't like placeholders
	my $engine = $MembersExternal_Context{ engine };
	my $host = $MembersExternal_Context{ host };
	my $schema = $MembersExternal_Context{ schema };
	my $user = $MembersExternal_Context{ user };
	my $pass = $MembersExternal_Context{ pass };
	my $dsn = "DBI:$engine:server=$host;host=$host;database=$schema;sid=$schema";
	$MembersExternal_Context{ conn } = DBI->connect( $dsn, $user, $pass );
	unless ( defined $MembersExternal_Context{ conn } ) {
	    warn "MembersExternal:  Couldn't connect to external DB!: ". $DBI::errstr if ( $debug );
	    return undef;
	}
    }

    my $dbh = C4::Context->dbh;
    $query = "SELECT dblink FROM borrowers_external_structure WHERE dblink LIKE ?";
    $query .= " AND categorycode = ". $dbh->quote( $category ) if ( $category );
    my $sth = $dbh->prepare( $query );

    $query2 = "SELECT dblink FROM borrowers_external_structure WHERE dblink LIKE ? AND ( categorycode = '' OR categorycode IS NULL )";
    my $sth2 = $dbh->prepare( $query2 );

    # Clean up $columns
    #  Because the borrowers_external_structure fields must have table names,
    #  But the query results will not have them when using fetch_hashref
    #  So the parent sub probably cloned the fields without the table names
    #  to catch the value either way.
    foreach my $row ( @$columns ) {
	push @l_columns, $row if ( $row =~ /[^\.]+\.\S+/ );
    }

    # Figure out which tables we need now
    foreach my $row ( keys %$filters, @l_columns ) {
	my ( $table, $field );
	$row =~ /([^\.\s]*)\.\S+/;
	$tables{ $1 } = 1 if ( $1 );
    }
    # And figure out how to join them
    if ( scalar keys %tables > 1 ) {
	foreach ( keys %tables ) {
	    dbi_buildquerychain( $_, \%tables, \%weight, $sth, $sth2 );
	}
    } else {
	%weight = %tables;
    }

    # put together the query using keys %weight and the dblinks from the db
    #  then add the $filters
    my $first = 1;
    $query = "SELECT ". join ',', @l_columns;
    $query .= " FROM ";

    my ( @tbls, @joins );
    foreach my $tbl ( sort { $weight{$b} <=> $weight{$a} } keys %weight ) {
	push @tbls, $tbl;
	push @joins, $tables{ $tbl };
    }
    shift @joins;  # don't need the first one.

    $query .= join ' CROSS JOIN ', @tbls;
    $query .= " WHERE " if ( @joins );
    $query .= join ' AND ', @joins;

    if ( %$filters ) {
	my @filter_array;
	foreach my $attrib ( keys %$filters ) {
	    my $value = ( $$filters{ $attrib } =~ /\D+/ ) ? $MembersExternal_Context{ conn }->quote( $$filters{ $attrib } ) : $$filters{ $attrib };
	    push @filter_array, "$attrib = $value";
	}
	unless ( $query =~ / WHERE / ) {
	    $query .= " WHERE ";
	} else {
	    $query .= " AND ";
	}
	$query .= join " AND ", @filter_array;
    }

    $query =~ s/WHERE $//;  # clean up trailing WHERE if there are no conditions

    warn $query if ( $debug );
    return $query;
}

# recursively called function to figure out how to join tables for a query

sub dbi_buildquerychain {
    my ( $table, $tables, $weight, $sth, $sth2 ) = @_;
    my ( $found, $link, %links );
    my ( $t1, $t2 );

    our $depth++;
    if ( $depth > 1000 ) {  # Just in case
	warn "I really hope you aren't actually trying to chain together more than 1000 tables" if ( $debug );
	die;
    }

    $sth->execute( "\%$table\%" );  # this table links to...
    if ( $sth->rows ) {  # categorycode set or default set?
	while ( ( $link ) = $sth->fetchrow ) {
	    $links{ $link } = 1;
	}
	$sth->finish;
    } else {
	$sth2->execute( "\%$table\%" );
	while ( ($link ) = $sth2->fetchrow ) {
	    $links{ $link } = 1;
	}
	$sth2->finish;
    }

    foreach $link ( keys %links ) {  # for all the links we have so far...
	$link =~ /([^\.\s]+)\.[\S]+.*?\=.*?([^\.\s]+)\.[\S]+/;
	( $t1, $t2 ) = ( $1, $2 );
	$found = ( $t1 eq $table ) ? $t2 : $t1;  # the table this one links to

	$$weight{ $found } = 0 unless exists $$weight{ $found };  # init their
	$$weight{ $table } = 0 unless exists $$weight{ $table };  #  weight
	if ( exists $$tables{ $found } and $$tables { $found } ne "SEARCH" and $$weight{ $found } >= $$weight{ $table } ) {
	    $$weight{ $table }++;  # we've seen $table and $found before
	    $$weight{ $found } += $$weight{ $table } + 1;  # favor $found
	    $$tables{ $table } = $link;
	} elsif ( ! exists $$tables{ $found } ) {
	    my $temp = $$tables{ $table };  # we haven't see $found before
	    $$tables{ $table } = "SEARCH";  # search for it
	    my $chain = dbi_buildquerychain( $found, $tables, $weight, $sth, $sth2 );
	    if ( $temp ) {
		$$tables{ $table } = $temp;
	    } else {
		delete $$tables{ $table };
	    }
	    if ( $chain ) {  # chain found and it's link recorded
		$$weight{ $table }++;
		$$weight{ $found } += $$weight{ $table } + 1;
		$$tables{ $table } = $link;
	    }
	}
	delete $$weight{ $found } unless $$weight{ $found } > 0;
	delete $$weight{ $table } unless $$weight{ $table } > 0;
    }

    $depth--;
    return $$tables{ $table };
}

=item &GetMemberDetails_LDAP

=cut

sub GetMemberDetails_LDAP {
    my ( $cardnumber, $category ) = @_;
    my ( @columns, $filter );
    my ( $data, $result );

    @columns = GetExternalAllAttribs( $category );
    my $filter_field = GetExternalAttrib( 'cardnumber', $category );
    $filter = "$filter_field=$cardnumber";

    $data = ldap_search( $filter, \@columns );

    foreach my $row ( @$data ) {
	my ( $attrib, $value ) = @$row;
	my $field = GetExternalField( $attrib, $category );
	$$result{ $field } = $value;
    }

    return $result;
}

=item &GetMemberColumns_LDAP

=cut

sub GetMemberColumns_LDAP {
    my ( $columns, $branch, $data ) = @_;
    my ( %attribs, @all_cats );

    @all_cats = GetExternalMappedCategories();

    unless ( @all_cats ) {
	warn "GetMemberColumns called but no patron categories mapped" if $debug;
	return $data;
    }

    foreach my $cat ( @all_cats ) {
	foreach my $col ( @$columns ) {
	    my $attr = GetExternalAttrib( $col, $cat );
	    if ( $attr ) {
		$attr =~ /^[^\.]*\.?(\S+)/;
		my $short_attr = $1;
		$attribs{ $cat }{ $attr } = $col;
		$attribs{ $cat }{ $short_attr } = $col;
	    }
	}
    }

    foreach my $cat ( keys %attribs ) {
	my $branch_attr = GetExternalAttrib( 'branchcode', $cat );
	my $cardno_attr = GetExternalAttrib( 'cardnumber', $cat );
	my $filter;
	my @columns = keys %{ $attribs{ $cat } };
	$filter = "$branch_attr=$branch" if ( $branch );

	foreach my $search_attr ( @columns ) {
	    my $temp_filter = "$search_attr=*";
	    $temp_filter = '&('. $temp_filter .')('. $filter .')' if ($filter);
	    my $patrons = ldap_search( $temp_filter, [ $cardno_attr, $search_attr ] );

	    my ( $field, $temp_value, $card );
	    foreach my $row ( @$patrons ) {
		my ( $attrib, $value ) = @$row;
		if ( $attrib eq $cardno_attr ) {
		    $card = $value;
		} else {
		    $field = GetExternalField( $attrib, $cat );
		    $temp_value = $value;
		}
		if ( $card && $temp_value ) {  # once we have both...
		    $$data{ $card }{ $field } = $temp_value;
		}
	    }
	}
    }

    %attribs = ();
    foreach my $patron ( values %$data ) {  # simulate `select distinct` here
	foreach ( keys %$patron ) {
	    $attribs{ $_ }{ $$patron{ $_ } } = 1;
	}
    }
    foreach ( keys %attribs ) {
	$attribs{ $_ } = [ keys %{ $attribs{ $_ } } ];
    }
    return \%attribs;
}

=item &ListMembers_LDAP

=cut

sub ListMembers_LDAP {
    my ( $category, $branch ) = @_;
    my ( $query, $filter, %list );

    my $cardfield = GetExternalAttrib( 'cardnumber', $category );
    if ( $branch ) {
	my $branchfield = GetExternalAttrib( 'branchcode', $category );
	$filter = "$branchfield=$branch";
    }

    my $patrons = ldap_search( $filter, [ $cardfield ] );

    foreach my $row ( @$patrons ) {
	my ( $attrib, $value ) = @$row;
	$list{ $value } = 1;
    }

    return \%list;
}

=item &ModMember_LDAP

Ok, so I lied.  I'd done a couple of these for the Koha 2.2 code, so I ported them.

=cut

sub ModMember_LDAP {
    my ( $data, $category ) = @_;
    my ( $dn, %entry );

    $dn = LDAP_get_userdn( undef, $$data{borrowernumber}, $category );

    # Setup for ldap_modify
    foreach ( keys %$data ) {
	my $attrib = GetExternalAttrib( $_, $category );
	$entry{ $attrib } = $$data{ $_ } if ( $attrib );
    }

    if ( %entry ) {
	ldap_modify( $dn, \%entry );
    }
}

=item &DelMember_LDAP

This one still needs someone to fill it in.

=cut

sub DelMember_LDAP {
}

=item &AddMember_LDAP

=cut

sub AddMember_LDAP {
    my ( $data, $category ) = @_;
    my ( $dn, %entry );

    my $userfield = GetExternalAttrib( 'userid', $category );
    return unless ( $$data{ userid } && $userfield );  # need userid for the DN
    #  This isn't very clean.
    #  Basically just throwing stuff at the base of the directory.
    $dn = "$userfield=$$data{userid},". $MembersExternal_Context{ schema };

    # Setup for ldap_add
    foreach ( keys %$data ) {
	my $attrib = GetExternalAttrib( $_, $category );
	$entry{ $attrib } = $$data{ $_ } if ( $attrib );
    }

    if ( %entry ) {
	ldap_add( $dn, \%entry );
    }
}

=item &Check_Userid_LDAP

=cut

sub Check_Userid_LDAP {
    my ( $userid, $borrnum, $category ) = @_;
    my ( $filter, $result );

    my $card = GetMemberCardnumber( $borrnum );
    my $cardfield = GetExternalAttrib( 'cardnumber', $category );
    my $userfield = GetExternalAttrib( 'userid', $category );
    $filter = "$userfield=$userid";

    $result = ldap_search( $filter, [ $cardfield ] );

    foreach my $row ( @$result ) {
	my ( $attrib, $value ) = @$row;
	if ( $attrib eq $cardfield && $value ne $card ) {
	    return 0;
	}
    }

    return 1;
}

=item &checkpw_LDAP

=cut

sub checkpw_LDAP {
    my ( $userid, $password, $categories ) = @_;
    my ( $temp, $info, $filter, $cardfield, $passwd_field, $foundcat );

    foreach my $cat ( keys %$categories ) {
	$filter = "$$categories{ $cat }=$userid";
	$cardfield = GetExternalAttrib( 'cardnumber', $cat );
	$passwd_field = GetExternalAttrib( 'password', $cat );

	my $data = ldap_search( $filter, [ $cardfield, $passwd_field ] );
	#  Check for uniqueness
	if ( scalar @$data > 1 ) {
	    $debug && warn "MembersExternal Auth: got more than one userid match in external database for this category";
	    return;
	}
	if ( $foundcat && @$data ) {
	    $debug && warn "MembersExternal Auth: got more than one userid match across all categories for external database";
	    return;
	}
	if ( @$data ) {
	    $foundcat = $cat;
	    foreach my $row ( @$data ) {
		my ( $attrib, $value ) = @$row;
		if ( $attrib eq $cardfield ) {
		    $info = $value;
		}
		if ( $attrib eq $passwd_field && $value eq $password ) {
		    $temp = 1;
		}
		if ( $info && $temp ) {
		    last;
		}
	    }
	}
    }

    return $info;
}

=item &LDAP_connect

Connect to the directory.  This stores the connection and bind in C<MembersExternal_Context> for later.

=cut

sub LDAP_connect {
    return if ( $MembersExternal_Context{ conn } && $MembersExternal_Context{ link } );

    my $ldap_conn = $MembersExternal_Context{ conn } || Net::LDAP->new( $MembersExternal_Context{ host } );
    my $ldap_bind = $MembersExternal_Context{ bind } || $ldap_conn->bind( $MembersExternal_Context{ user }, password => $MembersExternal_Context{ password }, version => 3 );

    $ldap_conn->sync unless ( $ldap_bind->code );
    if ( $ldap_conn && ! $ldap_bind->code ) {
	$MembersExternal_Context{ conn } = $ldap_conn;
	$MembersExternal_Context{ bind } = $ldap_bind;
    } else {
	warn "MembersExternal LDAP Couldn't connect.  Server down?  Invalid bind?" if $debug;
    }
}

=item &LDAP_get_userdn
    $dn = &LDAP_get_userdn( $cardnumber, $borrowernumber, $category );

Returns the DN for a borrower identified by C<$cardnumber>, or C<$borrowernumber>.

=cut

sub LDAP_get_userdn {
    my ( $cardnumber, $borrnum, $category ) = @_;
    my $dn;

    if ( $borrnum && ! $cardnumber ) {
	$cardnumber = GetMemberCardnumber( $borrnum );
    }

    my $card_field = GetExternalAttrib( 'cardnumber', $category );

    my $ldap_dnfield = $MembersExternal_Context{ DNfield };
    my $result = ldap_search( "$card_field=$cardnumber", [ $ldap_dnfield ] );
    foreach my $row ( @$result ) {
	my ( $attrib, $value ) = @$row;
	$dn = $value if ( $attrib eq $ldap_dnfield );
    }

    return $dn;
}

=item &LDAP_search
    $records = &LDAP_search( $filter, $fields );

Search the directory.  This does most of the heavy lifting when MembersExternal is connected to a directory.

C<$filter> limits to certain records.  This should be the patrons DN unless you want everyone.
C<$fields> limits to certain attributes.

Returns and array-ref that contains array-refs containing the attribute, value pairs found by the search.

=cut

sub LDAP_search {
    my ( $filter, $fields ) = @_;
    my ( $ldap_conn, $ldap_bind, $ldap_basedn );

    unless ( $filter ) {
	$filter = "name=*";
	warn "MembersExternal LDAP ldap_search(): No filter given" if $debug;
    }

    $ldap_conn = $MembersExternal_Context{ conn };
    $ldap_bind = $MembersExternal_Context{ bind };
    $ldap_basedn = $MembersExternal_Context{ schema };

    LDAP_connect() unless ( $ldap_bind );  # make sure we are connected

    if ( $ldap_conn ) {
	my $result = $ldap_conn->search(
	    base => $ldap_basedn,
	    filter => $filter,
	    attrs => $fields
	    );

	return undef if ( $result->code );

	my @found;
	foreach my $entry ( $result->entries ) {
	    foreach my $attr ( sort $entry->attributes ) {
		foreach my $value ( $entry->get_value( $attr ) ) {
		    push @found, [ $attr, $value ] if ( $value );
		}
	    }
	}
	return \@found;
    }
    return undef;
}

=item &LDAP_add

Add a record to the directory.

=cut

sub LDAP_add {
    my ( $dn, $entry ) = @_;
    my $result;

    my $ldap_conn = $MembersExternal_Context{ conn };
    my $ldap_bind = $MembersExternal_Context{ bind };
    my $ldap_basedn = $MembersExternal_Context{ schema };

    ldap_connect() unless ( $ldap_bind );

    if ( $ldap_conn ) {
	$result = $ldap_conn->add( $dn, attrs => [%$entry] );
	$ldap_conn->sync();
    }

    warn "LDAP Add error: ". $result->error if ( $result->code && $debug );
    return $result->code;
}

=item &LDAP_modify

Modify an existing record in the directory.

=cut

sub LDAP_modify {
    my ( $dn, $entry ) = @_;
    my $result;

    my $ldap_conn = $MembersExternal_Context{ conn };
    my $ldap_bind = $MembersExternal_Context{ bind };
    my $ldap_basedn = $MembersExternal_Context{ schema };

    ldap_connect() unless ( $ldap_bind );

    if ( $ldap_conn ) {
	$result = $ldap_conn->modify( $dn, changes => [ replace => [ @$entry ] ] );
	$ldap_conn->sync();
    }

    warn "LDAP Modify error: ". $result->error if ( $result->code && $debug );
    return $result->code;
}

END { }    # module clean-up code here (global destructor)

1;

__END__

=back

=head1 AUTHOR

Michael Hafen for WCSD

=cut
