# RELEASE NOTES FOR KOHA 25.05.09
21 Apr 2026

Koha is the first free and open source software library automation
package (ILS). Development is sponsored by libraries of varying types
and sizes, volunteers, and support companies from around the world. The
website for the Koha project is:

- [Koha Community](https://koha-community.org)

Koha 25.05.09 can be downloaded from:

- [Download](https://download.koha-community.org/koha-25.05.09.tar.gz)

Installation instructions can be found at:

- [Koha Wiki](https://wiki.koha-community.org/wiki/Installation_Documentation)
- OR in the INSTALL files that come in the tarball

Koha 25.05.09 is a bugfix/maintenance release.

It includes 1 enhancements, 31 bugfixes.

**System requirements**

You can learn about the system components (like OS and database) needed for running Koha on the [community wiki](https://wiki.koha-community.org/wiki/System_requirements_and_recommendations).


#### Security bugs

- [41261](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41261) XSS vulnerability in opac/unAPI
  >This change validates the inputs to "unapi" so that any invalid inputs will result in a 400 error or a response containing valid options for follow-up requests.
- [41594](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41594) Can access invoice-files.pl even when AcqEnableFiles is disabled
  >26.05.00, 25.11.03
- [42048](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=42048) Reflected XSS in patron search saved link
  >26.05.00, 25.11.03

## Bugfixes

### Acquisitions

#### Other bugs fixed

- [41420](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41420) Syntax error in referrer in parcel.tt
  >This fixes the URL for the "Cancel order and catalog record" link when receiving an order for an invoice - the referrer section of the URL was missing.

### Architecture, internals, and plumbing

#### Critical bugs fixed

- [41617](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41617) CSV export from item search results - incorrect spaces after comma separator causes issues
  >This fixes the CSV export from item search results in the staff interface (Search > Item search> Export select results (X) to CSV).
  >
  >It removes extra spaces after the comma separator, which causes issues when using the CSV file with some applications (such as Microsoft Excel).

#### Other bugs fixed

- [41142](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41142) Update jQuery-validate plugin to 1.21.0

  **Sponsored by** *Athens County Public Libraries*

### Cataloging

#### Critical bugs fixed

- [41481](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41481) XML validation error when launching the tag editor for MARC21 fields 006/008
  >This fixes an XML validation error ("Can't validate the xml data from (...)/marc21_field_00{6,8}.xml") when using the tag editor for MARC21 fields 006/008. The tag editor now works as expected for these fields.

#### Other bugs fixed

- [34879](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=34879) ./catalogue/getitem-ajax.pl appears to be unused
- [41475](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41475) 500 error when placing a hold on records with multiple 773 entries
- [41588](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41588) Link from 856$u breaks with leading or trailing spaces
  >If a 856$u for a record had spaces before or after the URL, the link shown on the record page on the OPAC and staff interface (under 'Online resources') did not work.
  >
  >Depending on the browser, either nothing happened, or an error was shown that the site wasn't reachable.
  >
  >Examples that previously caused links not to work (without the quotes):
  >- " koha-community.org"
  >- "koha-community.org "
  >- " koha-community.org "

### Circulation

#### Other bugs fixed

- [41055](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41055) Missing accesskey attribute for print button (shortcut P)

  **Sponsored by** *Koha-Suomi Oy*
- [41345](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41345) Regression: Clicking the 'Ignore' button on hold found modal for already-waiting hold does not dismiss the modal (again)
  >This fixes a regression when checking in an item. Clicking the "Ignore" option in the dialog box, when an item already has a waiting status, just reloaded the dialog box. Clicking the "Ignore" option now closes the dialog box and works as expected.

### I18N/L10N

#### Other bugs fixed

- [41623](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41623) Missing translation string in catalogue_detail.inc (again)
- [41689](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41689) "Staff note" and "OPAC" message types in patron files untranslatable

### ILL

#### Other bugs fixed

- [41237](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41237) OPAC created requests ignore library selection, always default to patron's library
  >This fixes a bug on the OPAC create ILL request form which was always setting the library to the patron's library, ignoring the library selection made on the form.
- [41465](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41465) Unauthenticated request does not display 'type' correctly
- [41478](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41478) AutoILLBackendPriority - Unauthenticated request shows backend form if wrong captcha
- [41512](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41512) ILLCheckAvailability stage table doesn't render
  >This fixes creating ILL requests when the ILLCheckAvailability system preference is used - the checking for availability was not completed and the table was not shown.

### Notices

#### Other bugs fixed

- [40960](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40960) Only generate a notice for patrons about holds filled if they have set messaging preferences
  >Currently, if a patron has not set any messaging preferences for notifying them about holds filled, a print notice is still generated.
  >
  >With this change, a notice is now only generated for a patron if their messaging preferences for 'Hold filled' are set. This matches the behavor for overdue and hold reminder notices.

### Patrons

#### Other bugs fixed

- [41040](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41040) Empty patron search from the header should not trigger a patron search
  >This fixes the "Search patrons" option in the staff interface menu bar. Currently, clicking "Search patrons" and then the arrow (without entering a value) automatically performs a search.
  >
  >With this change, a patron search is now no longer automatic. If you don't enter anything, or don't select any options, you are now prompted (using a tooltip) to enter a patron name or card number.
  >
  >NOTE: This is a change in behavour from what you may be used to.
- [41752](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41752) Guarantor first name and guarantor surname mislabeled in system preferences

### SIP2

#### Other bugs fixed

- [41458](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41458) SIP passes UID instead of GID to Net::Server causing error
  >This fixes an error that may occur when starting the SIP server: "...Couldn't become gid "<uid>": Operation not permitted...". Koha was passing an incorrect value to the Net::Server "group" parameter.

### Serials

#### Other bugs fixed

- [36466](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=36466) Incorrect date value stored when "Published on" or "Expected on" are empty
  >Editing a serial and removing the dates in the "Published on" and "Expected on" fields generated a 500 error (Serials > [selected serial] > Serial collection).
  >
  >This fixes the error and:
  >- Sets the data in the database to NULL
  >- Shows the dates as "Unknown" in the serial collection table for the "Date published" and "Date received" columns
  >- Changes any existing 0000-00-00 dates in the database to NULL (for existing installations)

### Staff interface

#### Other bugs fixed

- [41422](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41422) New FilterSearchResultsByLoggedInBranch doesn't fully translate
  >This fixes the translatability of the text shown when the FilterSearchResultsByLoggedInBranch system preference is enabled, and also the check and what is shown only works when not translated.
- [41679](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41679) Stock rotation repatriation modal can conflict with holds modal

### System Administration

#### Critical bugs fixed

- [41431](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41431) Circulation rule notes dropping when editing rule
  >This fixes editing circulation and fine rules with notes - notes are now correctly shown when editing, and are not lost when saving the rule.
  >
  >Previously, if you edited a rule with a note, it was not displayed in the edit field and was removed when the rule was saved.

  **Sponsored by** *Koha-Suomi Oy*

#### Other bugs fixed

- [19690](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=19690) Smart rules: Term "If any unavailable" is confusing
- [41540](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41540) staffShibOnly - update description for system preference
  >This updates the description for the `staffShibOnly` system preference and fixes grammar and spelling:
  >- "login" to "log in"
  >- "shibboleth" to "Shibboleth" (capitalized)

### Templates

#### Other bugs fixed

- [41351](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41351) Capitalization: Override Renew hold for another
  >This fixes the capitalization for a log viewer message: "Override Renew hold for another" to "Override renew hold for another".
- [41764](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41764) ISSN hidden input missing from Z39.50 search form navigation
  >This fixes the Acquisitions and Cataloging Z39.50 search forms so that the pagination works when searching using the ISSN input field.
  >
  >When you click the next page of results, or got to a specific result page, the search now works as expected - it remembers the ISSN you were searching for, with "You searched for: ISSN: XXXX" shown above the search results, and search results shown.
  >
  >Previously, the ISSN was not remembered, and "Nothing found. Try another search." was shown, and no further search results were shown.

  **Sponsored by** *Athens County Public Libraries*

### Test Suite

#### Other bugs fixed

- [41449](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41449) Reserves.t may fail when on shelf holds are restricted

## Enhancements 

### OPAC

#### Enhancements

- [41655](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41655) Local OPAC covers are not displayed in OPAC lists
  >This fixes a regression where the local cover images were no longer displayed in lists in the OPAC and staff interface. With this fix, the local cover images are back in the lists in both interfaces.

## Documentation

The Koha manual is maintained in Sphinx. The home page for Koha
documentation is

- [Koha Documentation](https://koha-community.org/documentation/)
As of the date of these release notes, the Koha manual is available in the following languages:

- [English (USA)](https://koha-community.org/manual/25.05/en/html/)
- [French](https://koha-community.org/manual/25.05/fr/html/) (80%)
- [German](https://koha-community.org/manual/25.05/de/html/) (89%)
- [Greek](https://koha-community.org/manual/25.05/el/html/) (93%)
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
- French (100%)
- French (Canada) (99%)
- German (99%)
- Greek (65%)
- Hindi (94%)
- Italian (81%)
- Norwegian Bokmål (71%)
- Persian (fa_ARAB) (93%)
- Polish (99%)
- Portuguese (Brazil) (99%)
- Portuguese (Portugal) (88%)
- Russian (93%)
- Slovak (59%)
- Spanish (98%)
- Swedish (89%)
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

The release team for Koha 25.05.09 is


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
new features in Koha 25.05.09
<div style="column-count: 2;">

- Athens County Public Libraries
- [Koha-Suomi Oy](https://koha-suomi.fi)
</div>

We thank the following individuals who contributed patches to Koha 25.05.09
<div style="column-count: 2;">

- Pedro Amorim (8)
- Tomás Cohen Arazi (1)
- David Cook (4)
- Jonathan Druart (2)
- Laura Escamilla (3)
- Andrew Fuerste-Henry (3)
- Lucas Gass (3)
- Ayoub Glizi-Vicioso (1)
- Kyle M Hall (3)
- Owen Leonard (5)
- Photonyx (1)
- Martin Renvoize (1)
- Marcel de Rooy (2)
- Caroline Cyr La Rose (1)
- Andreas Roussos (1)
- Slava Shishkin (2)
- Emmi Takkinen (1)
- Hammat Wele (4)
- Baptiste Wojtkowski (3)
- Samuel Young (1)
</div>

We thank the following libraries, companies, and other institutions who contributed
patches to Koha 25.05.09
<div style="column-count: 2;">

- Athens County Public Libraries (5)
- [BibLibre](https://www.biblibre.com) (3)
- [ByWater Solutions](https://bywatersolutions.com) (12)
- [Dataly Tech](https://dataly.gr) (1)
- Independant Individuals (4)
- Koha Community Developers (2)
- [Koha-Suomi Oy](https://koha-suomi.fi) (1)
- [OpenFifth](https://openfifth.co.uk) (9)
- [Prosentient Systems](https://www.prosentient.com.au) (4)
- Rijksmuseum, Netherlands (2)
- [Solutions inLibro inc](https://inlibro.com) (6)
- [Theke Solutions](https://theke.io) (1)
</div>

We also especially thank the following individuals who tested patches
for Koha
<div style="column-count: 2;">

- Richard Bridgen (1)
- Nick Clemens (2)
- David Cook (1)
- Roman Dolny (1)
- Jonathan Druart (8)
- Laura Escamilla (43)
- Katrin Fischer (3)
- Andrew Fuerste-Henry (1)
- Lucas Gass (11)
- Stephen Graham (2)
- Kyle M Hall (10)
- Jan Kissig (1)
- Owen Leonard (9)
- David Nind (26)
- Martin Renvoize (2)
- Marcel de Rooy (6)
- Caroline Cyr La Rose (1)
- Lisette Scheer (3)
- Emmi Takkinen (2)
- Baptiste Wojtkowski (1)
- Anneli Österman (1)
</div>





We regret any omissions.  If a contributor has been inadvertently missed,
please send a patch against these release notes to koha-devel@lists.koha-community.org.

## Revision control notes

The Koha project uses Git for version control.  The current development
version of Koha can be retrieved by checking out the main branch of:

- [Koha Git Repository](https://git.koha-community.org/koha-community/koha)

The branch for this version of Koha and future bugfixes in this release
line is 25.05.x.

## Bugs and feature requests

Bug reports and feature requests can be filed at the Koha bug
tracker at:

- [Koha Bugzilla](https://bugs.koha-community.org)

He rau ringa e oti ai.
(Many hands finish the work)

Autogenerated release notes updated last on 21 Apr 2026 23:56:15.
