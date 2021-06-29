$DBversion = 'XXX'; # will be replaced by the RM
if( CheckVersion( $DBversion ) ) {
    $dbh->do( "INSERT IGNORE INTO systempreferences (variable, value, options, explanation, type) VALUES ('IndependentBranchesHideOtherBranchesItems','0','','Hide other branches in selects.  Hide items belonging to other branches in search results, holds, biblio and item details, and exports.','YesNo')" );
    NewVersion( $DBversion, 28642, "Add new systempreference IndependentBranchesHideOtherBranchesItems");
}
