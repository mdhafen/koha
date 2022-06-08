package WCSDVersion;

# Copyright 2015 BibLibre
# Copyright 2015 Theke Solutions
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

use vars qw{ $VERSION };

#the version is divided in 2 parts :
# - #1 : the release counter. i.e. 26
# - #2 : the database version.
#        used by developers when the database changes.
#        wcsd_update takes care of the changes itself,
#        and is automatically called by Auth.pm when needed.
$VERSION = "5.004";

sub version {
    return $VERSION;
}

1;

=head1 NAME

WCSDVersion - Fork specific version for tracking database changes.

=head1 SYNOPSIS

At the moment this module only provides a version subroutine.

=head1 METHODS

=head2 version

    use WCSDVersion;

    my $version = WCSDVersion::version;

=head1 SEE ALSO

Koha.pm

C4::Context

=head1 AUTHORS

Michael Hafen <michael.hafen@washk12org>

=cut
