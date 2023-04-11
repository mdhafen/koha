use Modern::Perl;

return {
    bug_number => "32105",
    description => "Add patron list users table",
    up => sub {
        my ($args) = @_;
        my ($dbh, $out) = @$args{qw(dbh out)};
        unless ( TableExists('patron_list_users') ) {
            $dbh->do(q{CREATE TABLE `patron_list_users` (
  `patron_list_user_id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'unique identifier',
  `patron_list_id` int(11) NOT NULL COMMENT 'the list this entry is part of',
  `borrowernumber` int(11) NOT NULL COMMENT 'the borrower that is given access to this list',
  `can_edit` tinyint(1) NOT NULL DEFAULt 0 COMMENT 'whether this borrower can edit the list and it''s patrons',
  PRIMARY KEY (`patron_list_user_id`),
  KEY `patron_list_id` (`patron_list_id`),
  KEY `borrowernumber` (`borrowernumber`),
  CONSTRAINT `patron_list_users_ibfk_1` FOREIGN KEY (`patron_list_id`) REFERENCES `patron_lists` (`patron_list_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `patron_list_users_ibfk_2` FOREIGN KEY (`borrowernumber`) REFERENCES `borrowers` (`borrowernumber`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci});
            say $out "Added new table 'patron_list_users'";

            $dbh->do(q{ALTER TABLE patron_lists MODIFY shared tinyint DEFAULT 0 COMMENT '1 for everyone, 2 for library and individuals, 3 for individuals'});
            say $out "Add additional share modes to patron_lists table comment";
        }
    },
};
