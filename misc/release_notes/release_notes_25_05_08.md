# RELEASE NOTES FOR KOHA 25.05.08
24 Feb 2026

Koha is the first free and open source software library automation
package (ILS). Development is sponsored by libraries of varying types
and sizes, volunteers, and support companies from around the world. The
website for the Koha project is:

- [Koha Community](https://koha-community.org)

Koha 25.05.08 can be downloaded from:

- [Download](https://download.koha-community.org/koha-25.05.08.tar.gz)

Installation instructions can be found at:

- [Koha Wiki](https://wiki.koha-community.org/wiki/Installation_Documentation)
- OR in the INSTALL files that come in the tarball

Koha 25.05.08 is a bugfix/maintenance release.

It includes 11 enhancements, 9 bugfixes, 1 security bugfix.

**System requirements**

You can learn about the system components (like OS and database) needed for running Koha on the [community wiki](https://wiki.koha-community.org/wiki/System_requirements_and_recommendations).


#### Security bugs

- [41591](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41591) XSS vulnerability via file upload function for invoices

## Bugfixes

### Architecture, internals, and plumbing

#### Other bugs fixed

- [40995](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40995) Patron search autocomplete adds extraneous spacing and punctuation when patron lacks surname
- [41076](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41076) Perltidy config needs to be refined to not cause changes with perltidy 20250105
  >26.05.00

### ERM

#### Other bugs fixed

- [41001](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41001) Dismissing the "Run now" modal breaks functionality

### OPAC

#### Critical bugs fixed

- [41662](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41662) CSRF-vulnerability in opac-patron-consent.pl.

#### Other bugs fixed

- [41128](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41128) ratings.js creating "undefined" text for screen readers and print output

### REST API

#### Other bugs fixed

- [40219](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40219) Welcome Email Sent on Failed Patron Registration via API
  >This fixes patron registrations using the API - a welcome email notice was sent even if there were validation failures.

### Staff interface

#### Critical bugs fixed

- [41593](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41593) Authenticated SQL Injection in staff side suggestions

### Templates

#### Other bugs fixed

- [41361](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41361) Incorrect markup in category code confirmation modal
  >This fixes the "Confirm expiration date" dialog box that is shown when changing an individual patron's category:
  >- The "No" option now works.
  >- It is now formatted using our standard Bootstrap 5 styles.

  **Sponsored by** *Athens County Public Libraries*

## Enhancements 

### Accessibility

#### Enhancements

- [39706](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39706) Accessibility: Missing text alternative for the star rating.

### Architecture, internals, and plumbing

#### Enhancements

- [36674](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=36674) Lazy load api-client JS files

### Authentication

#### Enhancements

- [37711](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=37711) IdP auto-register should work on the staff interface
  >The 'auto-register' feature can now be enabled in the staff interface.
  >
  >Previously, this functionality was only available in the OPAC and could not be used from the staff side.

  **Sponsored by** *ByWater Solutions*

### Command-line Utilities

#### Enhancements

- [40722](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40722) Add logging to reset of elastic mappings files when rebuilding elastic

### MARC Bibliographic data support

#### Enhancements

- [29733](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=29733) MARC21: Link 7xx linking fields to marc21_linking_section.pl value builder in sample frameworks
- [40272](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40272) Add an alert for incorrect (MARC21) fixed-length control fields
  >This proposal adds an alert when opening the MARC basic editor while a control field (005-008) has an incorrect length.

### OPAC

#### Enhancements

- [18148](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=18148) Make list of lists in OPAC sortable
  >When reviewing a list of public or private lists in the OPAC, users can now sort the list of lists by "List name" or "Modification date" in ascending or descending order.

### Patrons

#### Enhancements

- [30568](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=30568) Make patron name fields more flexible
- [32581](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=32581) Update dateexpiry on categorycode change

### Plugin architecture

#### Enhancements

- [40827](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40827) Update plugin wrapper to include context for method="report"
  >This enhancement updates the plugin wrapper to include the reports menu and have the breadcrumbs list reports instead of admin or tools when method="report"

### REST API

#### Enhancements

- [39816](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=39816) Allow embedding `days_late` in baskets
  >This development adds the ability to embed information on late days on the basket objects retrieved from the API.

## Documentation

The Koha manual is maintained in Sphinx. The home page for Koha
documentation is

- [Koha Documentation](https://koha-community.org/documentation/)
As of the date of these release notes, the Koha manual is available in the following languages:

- [English (USA)](https://koha-community.org/manual/25.05/en/html/)
- [French](https://koha-community.org/manual/25.05/fr/html/) (74%)
- [German](https://koha-community.org/manual/25.05/de/html/) (90%)
- [Greek](https://koha-community.org/manual/25.05/el/html/) (94%)
- [Hindi](https://koha-community.org/manual/25.05/hi/html/) (63%)

The Git repository for the Koha manual can be found at

- [Koha Git Repository](https://gitlab.com/koha-community/koha-manual)

## Translations

Complete or near-complete translations of the OPAC and staff
interface are available in this release for the following languages:
<div style="column-count: 2;">

- Arabic (ar_ARAB) (92%)
- Armenian (hy_ARMN) (100%)
- Bulgarian (bg_CYRL) (100%)
- Chinese (Simplified Han script) (83%)
- Chinese (Traditional Han script) (97%)
- Czech (67%)
- Dutch (86%)
- English (100%)
- English (New Zealand) (61%)
- English (USA)
- Finnish (99%)
- French (99%)
- French (Canada) (99%)
- German (99%)
- Greek (65%)
- Hindi (94%)
- Italian (80%)
- Norwegian Bokmål (71%)
- Persian (fa_ARAB) (93%)
- Polish (99%)
- Portuguese (Brazil) (99%)
- Portuguese (Portugal) (87%)
- Russian (93%)
- Slovak (59%)
- Spanish (98%)
- Swedish (88%)
- Telugu (65%)
- Turkish (80%)
- Ukrainian (74%)
- Western Armenian (hyw_ARMN) (60%)
</div>

Partial translations are available for various other languages.

The Koha team welcomes additional translations; please see

- [Koha Translation Info](https://wiki.koha-community.org/wiki/Translating_Koha)

For information about translating Koha, and join the koha-translate 
list to volunteer:

- [Koha Translate List](https://lists.koha-community.org/cgi-bin/mailman/listinfo/koha-translate)

The most up-to-date translations can be found at:

- [Koha Translation](https://translate.koha-community.org/)

## Release Team

The release team for Koha 25.05.08 is


- Release Manager: Lucas Gass

- QA Manager: Martin Renvoize

- QA Team:
  - Marcel de Rooy
  - Martin Renvoize
  - Jonathan Druart
  - Laura Escamilla
  - Lucas Gass
  - Tomás Cohen Arazi
  - Lisette Scheer
  - Nick Clemens
  - Paul Derscheid
  - Emily Lamancusa
  - David Cook
  - Matt Blenkinsop
  - Andrew Fuerste-Henry
  - Brendan Lawlor
  - Pedro Amorim
  - Kyle M Hall
  - Aleisha Amohia
  - David Nind
  - Baptiste Wojtkowski
  - Jan Kissig
  - Katrin Fischer
  - Thomas Klausner
  - Julian Maurice
  - Owen Leonard

- Documentation Manager: David Nind

- Documentation Team:
  - Philip Orr
  - Aude Charillon
  - Caroline Cyr La Rose

- Translation Manager: Jonathan Druart


- Wiki curators: 
  - George Williams
  - Thomas Dukleth

- Release Maintainers:
  - 25.11 -- Jacob O'Mara
  - 25.05 -- Laura Escamilla
  - 24.11 -- Fridolin Somers
  - 22.11 -- Wainui Witika-Park (Catalyst IT)

- Release Maintainer assistants:
  - 25.11 -- Chloé Zermatten
  - 24.11 -- Baptiste Wojtkowski
  - 22.11 -- Alex Buckley & Aleisha Amohia

## Credits

We thank the following libraries, companies, and other institutions who are known to have sponsored
new features in Koha 25.05.08
<div style="column-count: 2;">

- Athens County Public Libraries
- [ByWater Solutions](https://bywatersolutions.com)
</div>

We thank the following individuals who contributed patches to Koha 25.05.08
<div style="column-count: 2;">

- Pedro Amorim (3)
- Tomás Cohen Arazi (10)
- Nick Clemens (4)
- David Cook (6)
- Paul Derscheid (2)
- Jonathan Druart (5)
- Laura Escamilla (8)
- Andrew Fuerste-Henry (2)
- Lucas Gass (3)
- Janusz Kaczmarek (1)
- Sam Lau (2)
- Owen Leonard (1)
- CJ Lynce (1)
- Nina Martinez (1)
- Martin Renvoize (1)
- Marcel de Rooy (2)
- Lisette Scheer (2)
- Leo Stoyanov (1)
</div>

We thank the following libraries, companies, and other institutions who contributed
patches to Koha 25.05.08
<div style="column-count: 2;">

- Athens County Public Libraries (1)
- [BibLibre](https://www.biblibre.com) (1)
- [ByWater Solutions](https://bywatersolutions.com) (20)
- Independant Individuals (3)
- Koha Community Developers (5)
- [LMSCloud](https://www.lmscloud.de) (2)
- [OpenFifth](https://openfifth.co.uk) (4)
- [Prosentient Systems](https://www.prosentient.com.au) (6)
- Rijksmuseum, Netherlands (2)
- [Theke Solutions](https://theke.io) (10)
- [Westlake Porter Public Library](https://westlakelibrary.org) (1)
</div>

We also especially thank the following individuals who tested patches
for Koha
<div style="column-count: 2;">

- Tomás Cohen Arazi (2)
- Christopher Brannon (1)
- Nick Clemens (2)
- David Cook (7)
- Paul Derscheid (1)
- Roman Dolny (2)
- Jonathan Druart (7)
- Laura Escamilla (42)
- Andrew Fuerste-Henry (1)
- Lucas Gass (2)
- Jan Kissig (3)
- Owen Leonard (5)
- David Nind (1)
- Martin Renvoize (12)
- Marcel de Rooy (4)
- Lisette Scheer (4)
- Sam Sowanick (4)
- Emmi Takkinen (2)
</div>





We regret any omissions.  If a contributor has been inadvertently missed,
please send a patch against these release notes to koha-devel@lists.koha-community.org.

## Revision control notes

The Koha project uses Git for version control.  The current development
version of Koha can be retrieved by checking out the main branch of:

- [Koha Git Repository](https://git.koha-community.org/koha-community/koha)

The branch for this version of Koha and future bugfixes in this release
line is 25.05.x-security.

## Bugs and feature requests

Bug reports and feature requests can be filed at the Koha bug
tracker at:

- [Koha Bugzilla](https://bugs.koha-community.org)

He rau ringa e oti ai.
(Many hands finish the work)

Autogenerated release notes updated last on 24 Feb 2026 21:16:58.
