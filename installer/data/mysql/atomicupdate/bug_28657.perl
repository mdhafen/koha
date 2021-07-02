$DBversion = 'XXX'; # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    $dbh->do( "ALTER TABLE `branches` MODIFY `branchip` mediumtext COLLATE utf8mb4_unicode_ci DEFAULT NULL COMMENT 'the IP address(s) for your library or branch'" );

    my $sth = $dbh->prepare("
        SELECT branchip,branchcode
        FROM branches
        WHERE branchip like '%*%'
    ");
    $sth->execute;
    my $results = $sth->fetchall_arrayref({});
    $sth = $dbh->prepare("
        UPDATE branches
	SET branchip = ?
        WHERE branchcode = ?
    ");
    foreach(@$results) {
	$_->{branchip} =~ s|\*||g;
        $sth->execute($_->{branchip}, $_->{branchcode});
    }

    NewVersion( $DBversion, 28657, "expand branches.branchip to allow for multiple ip ranges and remove '*'");
}
