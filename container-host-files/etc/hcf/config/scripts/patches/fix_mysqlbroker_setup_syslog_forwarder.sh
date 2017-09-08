set -e

PATCH_DIR="/var/vcap/jobs-src/cf-mysql-broker/templates"
PATCH_SENTINEL="${PATCH_DIR}/${0##*/}.sentinel"

if [ ! -f "${PATCH_SENTINEL}" ]; then
    patch -d "${PATCH_DIR}" --force -p 3 <<'PATCH'
diff --git jobs/cf-mysql-broker/templates/cf-mysql-broker_ctl.erb jobs/cf-mysql-broker/templates/cf-mysql-broker_ctl.erb
index fba7765f..0bccfb5e 100755
--- jobs/cf-mysql-broker/templates/cf-mysql-broker_ctl.erb
+++ jobs/cf-mysql-broker/templates/cf-mysql-broker_ctl.erb
@@ -36,8 +36,10 @@ case $1 in
     chown -R vcap:vcap $LOG_DIR

     <% if_p("syslog_aggregator.address", "syslog_aggregator.port", "syslog_aggregator.transport") do %>
+    # SCF: Disable
     # Start syslog forwarding
-    /var/vcap/packages/syslog_aggregator/setup_syslog_forwarder.sh $JOB_DIR/config
+    #/var/vcap/packages/syslog_aggregator/setup_syslog_forwarder.sh $JOB_DIR/config
+    # SCF: END
     <% end %>

     # Run the migrations only on the first node
PATCH
    touch "${PATCH_SENTINEL}"
fi

exit 0
