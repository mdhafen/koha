[% USE Koha %]

<div id="navmenu">
    <div id="navmenulist">

        <h4>Custom reports</h4>
        <h5>Catalog</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/custom/cat_titles_by_various.pl">Titles by various criteria</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_lost.pl">Copies by status</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/circ_reserves.pl">Titles on hold</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_items_noitype.pl">Items with no item type</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_nocallnumber.pl">Copies without a call number</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_newcopies.pl">New copies</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_age.pl">Collection age</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_inventory.pl">Catalog Inventory</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_usedbarcodes.pl">Used barcodes</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/cat_unusedbarcodes.pl">Unused barcodes</a></li>
        </ul>

        <h5>Circulation</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/custom/circ_issued.pl">Checked out copies</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/account_overdues_fines.pl">Overdue copies and fines</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/circ_stats_noissues.pl">Copies with no check outs</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/circ_all_issues.pl">All check outs</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/circ_yearly_total.pl">Yearly circulation totals</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/circ_monthly_total.pl">Monthly circulation totals</a></li>
        </ul>

        <h5>Patrons</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/custom/account_fines.pl">Fines</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/account_payments.pl">Payments</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/borrowers_messages.pl">Patron messages</a></li>
            <li><a href="/cgi-bin/koha/reports/custom/borrowers_by_status.pl">List patrons by status</a></li>
        </ul>

        <h5>Guided reports</h5>
            <ul>
                <li><a href="/cgi-bin/koha/reports/guided_reports.pl">Guided reports</a></li>
                [% IF ( CAN_user_reports_create_reports ) %]
                    <li><a href="/cgi-bin/koha/reports/guided_reports.pl?phase=Build%20new">Build new</a></li>
                [% END %]
                [% IF ( CAN_user_reports_execute_reports ) %]
                    <li><a href="/cgi-bin/koha/reports/guided_reports.pl?phase=Use%20saved">Use saved</a></li>
                [% END %]
                [% IF ( CAN_user_reports_create_reports ) %]
                    <li><a href="/cgi-bin/koha/reports/guided_reports.pl?phase=Create%20report%20from%20SQL">Create from SQL</a></li>
                [% END %]
            </ul>

        <h5>Statistics wizards</h5>
            <ul>
                <li><a href="/cgi-bin/koha/reports/acquisitions_stats.pl">Acquisitions</a></li>
                <li><a href="/cgi-bin/koha/reports/borrowers_stats.pl">Patrons</a></li>
                <li><a href="/cgi-bin/koha/reports/catalogue_stats.pl">Catalog</a></li>
                <li><a href="/cgi-bin/koha/reports/issues_stats.pl">Circulation</a></li>
                <li><a href="/cgi-bin/koha/reports/serials_stats.pl">Serials</a></li>
                <li><a href="/cgi-bin/koha/reports/cash_register_stats.pl">Cash register</a></li>
                <li><a href="/cgi-bin/koha/reports/reserves_stats.pl">Holds</a></li>
            </ul>

        [% IF plugins_enabled %]
            <h5>Report plugins</h5>
            <ul>
                <li><a href="/cgi-bin/koha/plugins/plugins-home.pl?method=report">Report plugins</a></li>
            </ul>
        [% END %]

        <h5>Top lists</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/bor_issues_top.pl">Patrons with the most checkouts</a></li>
            <li><a href="/cgi-bin/koha/reports/cat_issues_top.pl">Most-circulated items</a></li>
        </ul>

        <h5>Inactive</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/borrowers_out.pl">Patrons who haven't checked out</a></li>
            <li><a href="/cgi-bin/koha/reports/catalogue_out.pl">Items with no checkouts</a></li>
        </ul>


        <h5>Other</h5>
        <ul>
            <li><a href="/cgi-bin/koha/reports/itemslost.pl">Lost items</a></li>
            <li><a href="/cgi-bin/koha/reports/orders_by_fund.pl">Orders by fund</a></li>
            <li><a href="/cgi-bin/koha/reports/manager.pl?report_name=itemtypes">Catalog by item type</a></li>
            <li><a href="/cgi-bin/koha/reports/issues_avg_stats.pl">Average loan time</a></li>
        </ul>
    </div>
</div>
