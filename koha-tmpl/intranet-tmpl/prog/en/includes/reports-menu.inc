[% USE Koha %]
<div id="reports-menu" class="sidebar_menu icon-collapse">
    <h4>Custom reports</h4>

    <h5>Catalog</h5>
    <ul>
        <li><a href="/cgi-bin/koha/reports/custom/cat_titles_by_various.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Titles by various criteria</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_lost.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Copies by status</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/circ_reserves.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Titles on hold</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_items_noitype.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Items with no item type</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_nocallnumber.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Copies without a call number</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_newcopies.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">New copies</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_age.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Collection age</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_inventory.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Catalog Inventory</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_usedbarcodes.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Used barcodes</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/cat_unusedbarcodes.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Unused barcodes</span></a></li>
    </ul>

    <h5>Circulation</h5>
    <ul>
        <li><a href="/cgi-bin/koha/reports/custom/circ_issued.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Checked out copies</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/account_overdues_fines.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Overdue copies and fines</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/circ_stats_issues.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Titles with check out information</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/circ_all_issues.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">All check outs</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/circ_yearly_total.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Yearly circulation totals</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/circ_monthly_total.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Monthly circulation totals</span></a></li>
    </ul>

    <h5>Patrons</h5>
    <ul>
        <li><a href="/cgi-bin/koha/reports/custom/account_fines.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Fines</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/account_payments.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Payments</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/borrowers_messages.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">Patron messages</span></a></li>
        <li><a href="/cgi-bin/koha/reports/custom/borrowers_by_status.pl" title="Guided reports"><i class="fa-solid  fa-fw" aria-hidden="true"></i><span class="menu-label">List patrons by status</span></a></li>
    </ul>

    <h5>Guided reports</h5>
    <ul>
        <li
            ><a href="/cgi-bin/koha/reports/guided_reports.pl" title="Guided reports"><i class="fa-solid fa-file-lines fa-fw" aria-hidden="true"></i><span class="menu-label">Guided reports</span></a></li
        >
        [% IF ( CAN_user_reports_create_reports ) %]
            <li
                ><a href="/cgi-bin/koha/reports/guided_reports.pl?op=add_form" title="Build new"><i class="fa-solid fa-code-branch fa-fw" aria-hidden="true"></i><span class="menu-label">Build new</span></a></li
            >
        [% END %]
        [% IF ( CAN_user_reports_execute_reports_foreground || CAN_user_reports_execute_reports_background ) %]
            <li
                ><a href="/cgi-bin/koha/reports/guided_reports.pl?op=list" title="View saved"><i class="fa-solid fa-list fa-fw" aria-hidden="true"></i><span class="menu-label">View saved</span></a></li
            >
            <li
                ><a href="/cgi-bin/koha/reports/jobs.pl" title="Report jobs"><i class="fa-solid fa-list-check fa-fw" aria-hidden="true"></i> <span class="menu-label">Report jobs</span></a></li
            >
        [% END %]
        [% IF ( CAN_user_reports_create_reports ) %]
            <li
                ><a href="/cgi-bin/koha/reports/guided_reports.pl?op=add_form_sql" title="Create from SQL"><i class="fa-solid fa-plus fa-fw" aria-hidden="true"></i><span class="menu-label">Create from SQL</span></a></li
            >
        [% END %]
    </ul>

    <h5>Statistics wizards</h5>
    <ul>
        <li
            ><a href="/cgi-bin/koha/reports/acquisitions_stats.pl" title="Acquisitions"><i class="fa-solid fa-cart-shopping fa-fw" aria-hidden="true"></i><span class="menu-label">Acquisitions</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/borrowers_stats.pl" title="Patrons"><i class="fa-solid fa-users fa-fw" aria-hidden="true"></i><span class="menu-label">Patrons</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/catalogue_stats.pl" title="Catalog"><i class="fa-solid fa-book fa-fw" aria-hidden="true"></i><span class="menu-label">Catalog</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/issues_stats.pl" title="Circulation"><i class="fa-solid fa-arrow-right-arrow-left fa-fw" aria-hidden="true"></i><span class="menu-label">Circulation</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/serials_stats.pl" title="Serials"><i class="fa-solid fa-newspaper fa-fw" aria-hidden="true"></i><span class="menu-label">Serials</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/cash_register_stats.pl" title="Cash register"><i class="fa-solid fa-cash-register fa-fw" aria-hidden="true"></i><span class="menu-label">Cash register</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/reserves_stats.pl" title="Holds"><i class="fa-solid fa-bookmark fa-fw" aria-hidden="true"></i><span class="menu-label">Holds</span></a></li
        >
    </ul>

    [% IF plugins_enabled %]
        <h5>Report plugins</h5>
        <ul>
            <li
                ><a href="/cgi-bin/koha/plugins/plugins-home.pl?method=report" title="Report plugins"><i class="fa-solid fa-puzzle-piece fa-fw" aria-hidden="true"></i><span class="menu-label">Report plugins</span></a></li
            >
        </ul>
    [% END %]

    <h5>Top lists</h5>
    <ul>
        <li
            ><a href="/cgi-bin/koha/reports/bor_issues_top.pl" title="Patrons with the most checkouts"><i class="fa-solid fa-trophy fa-fw" aria-hidden="true"></i><span class="menu-label">Patrons with the most checkouts</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/cat_issues_top.pl" title="Most-circulated items"><i class="fa-solid fa-fire fa-fw" aria-hidden="true"></i><span class="menu-label">Most-circulated items</span></a></li
        >
    </ul>

    <h5>Inactive</h5>
    <ul>
        <li
            ><a href="/cgi-bin/koha/reports/borrowers_out.pl" title="Patrons who haven't checked out"><i class="fa-solid fa-user-clock fa-fw" aria-hidden="true"></i><span class="menu-label">Patrons who haven't checked out</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/catalogue_out.pl" title="Items with no checkouts"><i class="fa-solid fa-boxes-stacked fa-fw" aria-hidden="true"></i><span class="menu-label">Items with no checkouts</span></a></li
        >
    </ul>

    <h5>Other</h5>
    <ul>
        <li
            ><a href="/cgi-bin/koha/reports/itemslost.pl" title="Lost items"><i class="fa-solid fa-triangle-exclamation fa-fw" aria-hidden="true"></i><span class="menu-label">Lost items</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/orders_by_fund.pl" title="Orders by fund"><i class="fa-solid fa-money-bill-wave fa-fw" aria-hidden="true"></i><span class="menu-label">Orders by fund</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/catalog_by_itemtype.pl" title="Catalog by item type"><i class="fa-solid fa-shapes fa-fw" aria-hidden="true"></i><span class="menu-label">Catalog by item type</span></a></li
        >
        <li
            ><a href="/cgi-bin/koha/reports/issues_avg_stats.pl" title="Average loan time"><i class="fa-solid fa-hourglass-half fa-fw" aria-hidden="true"></i><span class="menu-label">Average loan time</span></a></li
        >
    </ul>
</div>
<!-- /.sidebar_menu -->
