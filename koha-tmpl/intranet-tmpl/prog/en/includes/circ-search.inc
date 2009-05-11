
<h1 id="logo"><a href="/cgi-bin/koha/mainpage.pl"><!-- TMPL_VAR NAME="LibraryName" --></a></h1><!-- Begin Circulation Resident Search Box -->

<div id="header_search">
    <!-- TMPL_INCLUDE NAME="patron-search-box.inc" -->
<!-- TMPL_IF NAME="CAN_user_circulate" -->
<div id="checkin_search" class="residentsearch" style="display:none;">
    <p class="tip">Scan a barcode to check in:</p>
    <form method="post" action="/cgi-bin/koha/circ/returns.pl">
        <input name="barcode" id="ret_barcode" size="40" accesskey="r" />
        <input value="Submit" class="submit" type="submit" />
    </form>
</div>
<div id="renew_search" class="residentsearch" style="display:none;">
    <p class="tip">Scan a barcode to renew:</p>
    <form method="post" action="/cgi-bin/koha/circ/renew.pl">
    <!-- TMPL_IF NAME="stickyduedate" -->
        <input type="hidden" name="stickyduedate" value="<!-- TMPL_VAR NAME="stickyduedate" -->" />
        <input type="hidden" name="duedatespec" value="<!-- TMPL_VAR NAME="duedatespec" -->" />
    <!-- /TMPL_IF -->
        <input name="barcode" id="ren_barcode" size="40" accesskey="n" />
        <input value="Submit" class="submit" type="submit" />
    </form>
</div>
<!-- /TMPL_IF -->
<!-- TMPL_IF NAME="CAN_user_catalogue" -->
<div id="catalog_search" class="residentsearch" style="display:none;">
    <p class="tip">Enter search keywords:</p>
    <form action="/cgi-bin/koha/catalogue/search.pl"  method="get" id="cat-search-block">
        <input type="text" name="q" id="search-form" size="40" accesskey="q" />
	<!-- TMPL_IF name="mylibraryfirst" -->
	<input name="limit" value="branch:<!-- TMPL_VAR name="LoginBranchcode" -->" type="hidden" />
	<!-- /TMPL_IF -->
        <input type="submit" class="submit" value="Submit"/>
    </form>
</div><!-- /TMPL_IF -->

<ul>
    <!-- TMPL_IF NAME="CAN_user_circulate" --><li><a href="/cgi-bin/koha/circ/circulation.pl#circ_search">Check Out</a></li><!-- /TMPL_IF -->
    <!-- TMPL_IF NAME="CAN_user_circulate" --><li><a href="/cgi-bin/koha/circ/returns.pl#checkin_search">Check In</a></li><!-- /TMPL_IF -->
    <!-- TMPL_IF NAME="CAN_user_circulate" --><li><a href="/cgi-bin/koha/circ/renew.pl#renew_search">Renew</a></li><!-- /TMPL_IF -->
    <!-- TMPL_IF NAME="CAN_user_catalogue" --><li><a href="/cgi-bin/koha/catalogue/search.pl#catalog_search">Search the Catalog</a></li><!-- /TMPL_IF -->
</ul>   

</div>

<!-- End Circulation Resident Search Box -->
