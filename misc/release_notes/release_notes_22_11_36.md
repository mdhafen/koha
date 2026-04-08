# RELEASE NOTES FOR KOHA 22.11.36
08 Apr 2026

Koha is the first free and open source software library automation
package (ILS). Development is sponsored by libraries of varying types
and sizes, volunteers, and support companies from around the world. The
website for the Koha project is:

- [Koha Community](https://koha-community.org)

Koha 22.11.36 can be downloaded from:

- [Download](https://download.koha-community.org/koha-22.11.36.tar.gz)

Installation instructions can be found at:

- [Koha Wiki](https://wiki.koha-community.org/wiki/Installation_Documentation)
- OR in the INSTALL files that come in the tarball

Koha 22.11.36 is a bugfix/maintenance release.

It includes 1 enhancements, 4 bugfixes.

**System requirements**

You can learn about the system components (like OS and database) needed for running Koha on the [community wiki](https://wiki.koha-community.org/wiki/System_requirements_and_recommendations).


#### Security bugs

- [41261](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41261) XSS vulnerability in opac/unAPI
  >This change validates the inputs to "unapi" so that any invalid inputs will result in a 400 error or a response containing valid options for follow-up requests.
- [41594](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41594) Can access invoice-files.pl even when AcqEnableFiles is disabled

## Bugfixes

### Patrons

#### Critical bugs fixed

- [41094](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=41094) search_anonymize_candidates returns too many candidates when FailedLoginAttempts is empty
  >This bug report fixes the selection of borrowers to be anonymized when that feature is enabled but FailedLoginAttempts is empty.

### SIP2

#### Other bugs fixed

- [40915](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=40915) SIP message parsing with empty fields edge cases

## Enhancements 

### Searching - Elasticsearch

#### Enhancements

- [33353](https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=33353) Add compatibility with Elasticsearch 8 and OpenSearch 2
  >These changes to support ElasticSearch 8.x and OpenSearch 2.x come with a loss of support for ElasticSearch 6.x.
  >
  >Existing instances will have to upgrade to either ElasticSearch 7.x or 8.x or OpenSearch 1.x or 2.x
  >
  >Upgrade from ES 7.x or OS 1.X to ES 8.x or OS 2.x require a reindexation.

## Documentation

The Koha manual is maintained in Sphinx. The home page for Koha
documentation is

- [Koha Documentation](https://koha-community.org/documentation/)
As of the date of these release notes, the Koha manual is available in the following languages:

- [English (USA)](https://koha-community.org/manual/22.11/en/html/)
- [French](https://koha-community.org/manual/22.11/fr/html/) (81%)
- [German](https://koha-community.org/manual/22.11/de/html/) (89%)
- [Greek](https://koha-community.org/manual/22.11/el/html/) (93%)
- [Hindi](https://koha-community.org/manual/22.11/hi/html/) (63%)

The Git repository for the Koha manual can be found at

- [Koha Git Repository](https://gitlab.com/koha-community/koha-manual)

## Translations

Complete or near-complete translations of the OPAC and staff
interface are available in this release for the following languages:
<div style="column-count: 2;">

- Arabic (ar_ARAB) (90%)
- Armenian (hy_ARMN) (100%)
- Bulgarian (bg_CYRL) (100%)
- Chinese (Simplified Han script) (96%)
- Chinese (Traditional Han script) (83%)
- Czech (73%)
- Dutch (89%)
- English (100%)
- English (New Zealand) (70%)
- English (USA)
- English (United Kingdom) (99%)
- Finnish (96%)
- French (100%)
- French (Canada) (96%)
- German (99%)
- German (Switzerland) (56%)
- Greek (72%)
- Hindi (99%)
- Italian (93%)
- Norwegian Bokmål (69%)
- Persian (fa_ARAB) (77%)
- Polish (99%)
- Portuguese (Brazil) (99%)
- Portuguese (Portugal) (88%)
- Russian (94%)
- Slovak (69%)
- Spanish (99%)
- Swedish (89%)
- Telugu (78%)
- Tetum (54%)
- Turkish (91%)
- Ukrainian (81%)
- Western Armenian (hyw_ARMN) (70%)
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

The release team for Koha 22.11.36 is


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



We thank the following individuals who contributed patches to Koha 22.11.36
<div style="column-count: 2;">

- Tomás Cohen Arazi (2)
- David Cook (2)
- Lucas Gass (1)
- Julian Maurice (2)
- Marcel de Rooy (2)
- Wainui Witika-Park (1)
</div>

We thank the following libraries, companies, and other institutions who contributed
patches to Koha 22.11.36
<div style="column-count: 2;">

- [BibLibre](https://www.biblibre.com) (2)
- [ByWater Solutions](https://bywatersolutions.com) (1)
- [Catalyst](https://www.catalyst.net.nz/products/library-management-koha) (1)
- [Prosentient Systems](https://www.prosentient.com.au) (2)
- Rijksmuseum, Netherlands (2)
- [Theke Solutions](https://theke.io) (2)
</div>

We also especially thank the following individuals who tested patches
for Koha
<div style="column-count: 2;">

- Jonathan Druart (1)
- Victor Grousset (2)
- Kyle M Hall (2)
- Owen Leonard (1)
- David Nind (2)
- Philip Orr (2)
- Martin Renvoize (4)
- Marcel de Rooy (1)
- Wainui Witika-Park (8)
- Baptiste Wojtkowski (1)
</div>





We regret any omissions.  If a contributor has been inadvertently missed,
please send a patch against these release notes to koha-devel@lists.koha-community.org.

## Revision control notes

The Koha project uses Git for version control.  The current development
version of Koha can be retrieved by checking out the main branch of:

- [Koha Git Repository](https://git.koha-community.org/koha-community/koha)

The branch for this version of Koha and future bugfixes in this release
line is 22.11.x-security.

## Bugs and feature requests

Bug reports and feature requests can be filed at the Koha bug
tracker at:

- [Koha Bugzilla](https://bugs.koha-community.org)

He rau ringa e oti ai.
(Many hands finish the work)

Autogenerated release notes updated last on 08 Apr 2026 16:36:26.
