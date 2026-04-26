#!/usr/bin/env bash
# Generate EJBCA certificate profile XML files for Phase 2
# Profiles: RootCAProd-ECC384-SHA384, SubordCAProd-ECC384-SHA384,
#           RootCAPilot-ECC384-SHA384, SubordCAPilot-ECC384-SHA384,
#           SubordCAPilot-RSA4096-SHA256

set -e
OUTDIR="$(dirname "$0")/profiles"
mkdir -p "$OUTDIR"

# -----------------------------------------------------------------------
# Helper: emit XML header/footer and common boilerplate
# type_int: 8=RootCA 2=SubCA
# validity: "3650d" "1825d" "90d"
# keyalg: "ECDSA" or "RSA"
# keyspec list: space-separated, e.g. "secp384r1" or "4096"
# keyusage: space-separated 9 booleans (digitalSig..decipherOnly)
# use_pathlen: true|false
# pathlen: 0 (only used when use_pathlen=true)
# cdp_uri: CRL distribution point URI
# caissuer_uri: caIssuers URI
# -----------------------------------------------------------------------
emit_profile() {
  local name="$1"
  local id="$2"
  local type_int="$3"
  local validity="$4"
  local keyalg="$5"
  local keyspec="$6"   # single keyspec value (curve name or bit length integer)
  local ku="$7"        # 9 space-separated booleans
  local use_pathlen="$8"
  local pathlen="$9"
  local cdp_uri="${10}"
  local caissuer_uri="${11}"

  local file="$OUTDIR/certprofile_${name}-${id}.xml"

  # Parse 9 key usage booleans
  read -r ku0 ku1 ku2 ku3 ku4 ku5 ku6 ku7 ku8 <<< "$ku"

  # Determine if key algo is RSA or ECDSA for algorithm list
  local algo_list=""
  if [ "$keyalg" = "ECDSA" ]; then
    algo_list='<void method="add"><string>ECDSA</string></void>'
  else
    algo_list='<void method="add"><string>RSA</string></void>'
  fi

  # For ECDSA: availableeccurves with the specific curve
  # For RSA: availablebitlengths with the specific bit length
  local curves_section=""
  local bitlengths_section=""
  if [ "$keyalg" = "ECDSA" ]; then
    curves_section="<void method=\"put\">
   <string>availableeccurves</string>
   <object class=\"java.util.ArrayList\">
    <void method=\"add\"><string>${keyspec}</string></void>
   </object>
  </void>
  <void method=\"put\">
   <string>availablebitlengths</string>
   <object class=\"java.util.ArrayList\">
    <void method=\"add\"><int>384</int></void>
   </object>
  </void>"
  else
    local ksbits="$keyspec"
    curves_section="<void method=\"put\">
   <string>availableeccurves</string>
   <object class=\"java.util.ArrayList\">
    <void method=\"add\"><string>ANY_EC_CURVE</string></void>
   </object>
  </void>
  <void method=\"put\">
   <string>availablebitlengths</string>
   <object class=\"java.util.ArrayList\">
    <void method=\"add\"><int>${ksbits}</int></void>
   </object>
  </void>"
  fi

  cat > "$file" << XMLEOF
<?xml version="1.0" encoding="UTF-8"?>
<java version="1.8.0_222" class="java.beans.XMLDecoder">
 <object class="java.util.LinkedHashMap">
  <void method="put">
   <string>version</string>
   <float>46.0</float>
  </void>
  <void method="put">
   <string>type</string>
   <int>${type_int}</int>
  </void>
  <void method="put">
   <string>certversion</string>
   <string>X509v3</string>
  </void>
  <void method="put">
   <string>encodedvalidity</string>
   <string>${validity}</string>
  </void>
  <void method="put">
   <string>usecertificatevalidityoffset</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>certificatevalidityoffset</string>
   <string>-10m</string>
  </void>
  <void method="put">
   <string>useexpirationrestrictionforweekdays</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>expirationrestrictionforweekdaysbefore</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>expirationrestrictionweekdays</string>
   <object class="java.util.ArrayList">
    <void method="add"><boolean>true</boolean></void>
    <void method="add"><boolean>true</boolean></void>
    <void method="add"><boolean>false</boolean></void>
    <void method="add"><boolean>false</boolean></void>
    <void method="add"><boolean>false</boolean></void>
    <void method="add"><boolean>true</boolean></void>
    <void method="add"><boolean>true</boolean></void>
   </object>
  </void>
  <void method="put">
   <string>allowvalidityoverride</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>description</string>
   <string>Phase 2 profile: ${name}</string>
  </void>
  <void method="put">
   <string>allowextensionoverride</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>allowdnoverride</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>allowdnoverridebyeei</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>allowbackdatedrevokation</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usecertificatestorage</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>storecertificatedata</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>storesubjectaltname</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>usebasicconstrants</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>basicconstraintscritical</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>usesubjectkeyidentifier</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>subjectkeyidentifiercritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useauthoritykeyidentifier</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>authoritykeyidentifiercritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usesubjectalternativename</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>subjectalternativenamecritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useissueralternativename</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>issueralternativenamecritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usecrldistributionpoint</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>usedefaultcrldistributionpoint</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>crldistributionpointcritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>crldistributionpointuri</string>
   <string>${cdp_uri}</string>
  </void>
  <void method="put">
   <string>usefreshestcrl</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usecadefinedfreshestcrl</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>freshestcrluri</string>
   <string></string>
  </void>
  <void method="put">
   <string>crlissuer</string>
   <string></string>
  </void>
  <void method="put">
   <string>usecertificatepolicies</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>certificatepoliciescritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>certificatepolicies</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>availablekeyalgorithms</string>
   <object class="java.util.ArrayList">
    ${algo_list}
   </object>
  </void>
  ${curves_section}
  <void method="put">
   <string>minimumavailablebitlength</string>
   <int>0</int>
  </void>
  <void method="put">
   <string>maximumavailablebitlength</string>
   <int>8192</int>
  </void>
  <void method="put">
   <string>signaturealgorithm</string>
   <null/>
  </void>
  <void method="put">
   <string>usekeyusage</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>keyusage</string>
   <object class="java.util.ArrayList">
    <void method="add"><boolean>${ku0}</boolean></void>
    <void method="add"><boolean>${ku1}</boolean></void>
    <void method="add"><boolean>${ku2}</boolean></void>
    <void method="add"><boolean>${ku3}</boolean></void>
    <void method="add"><boolean>${ku4}</boolean></void>
    <void method="add"><boolean>${ku5}</boolean></void>
    <void method="add"><boolean>${ku6}</boolean></void>
    <void method="add"><boolean>${ku7}</boolean></void>
    <void method="add"><boolean>${ku8}</boolean></void>
   </object>
  </void>
  <void method="put">
   <string>allowkeyusageoverride</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>keyusagecritical</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>useextendedkeyusage</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>extendedkeyusage</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>extendedkeyusagecritical</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>availablecas</string>
   <object class="java.util.ArrayList">
    <void method="add"><int>-1</int></void>
   </object>
  </void>
  <void method="put">
   <string>usedpublishers</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>useocspnocheck</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useldapdnorder</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>usecustomdnorder</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usemicrosofttemplate</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>microsofttemplate</string>
   <string></string>
  </void>
  <void method="put">
   <string>usecardnumber</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usecnpostfix</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>cnpostfix</string>
   <string></string>
  </void>
  <void method="put">
   <string>usesubjectdnsubset</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>subjectdnsubset</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>usesubjectaltnamesubset</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>subjectaltnamesubset</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>usepathlengthconstraint</string>
   <boolean>${use_pathlen}</boolean>
  </void>
  <void method="put">
   <string>pathlengthconstraint</string>
   <int>${pathlen}</int>
  </void>
  <void method="put">
   <string>useqcstatement</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usepkixqcsyntaxv2</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useauthorityinformationaccess</string>
   <boolean>true</boolean>
  </void>
  <void method="put">
   <string>caissuers</string>
   <object class="java.util.ArrayList">
    <void method="add"><string>${caissuer_uri}</string></void>
   </object>
  </void>
  <void method="put">
   <string>usedefaultcaissuer</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>usedefaultocspservicelocator</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>ocspservicelocatoruri</string>
   <string></string>
  </void>
  <void method="put">
   <string>cvcaccessrights</string>
   <int>3</int>
  </void>
  <void method="put">
   <string>usedcertificateextensions</string>
   <object class="java.util.ArrayList"/>
  </void>
  <void method="put">
   <string>approvals</string>
   <object class="java.util.LinkedHashMap"/>
  </void>
  <void method="put">
   <string>useprivkeyusageperiodnotbefore</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useprivkeyusageperiod</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>useprivkeyusageperiodnotafter</string>
   <boolean>false</boolean>
  </void>
  <void method="put">
   <string>privkeyusageperiodstartoffset</string>
   <long>0</long>
  </void>
  <void method="put">
   <string>privkeyusageperiodlength</string>
   <long>63072000</long>
  </void>
 </object>
</java>
XMLEOF

  echo "Created: $file"
}

CDP="http://ca.jsigroup.local/crl/root.crl"
AIA="http://ca.jsigroup.local/root.cer"

# Key Usage bits (index 0-8):
# 0:digitalSig 1:nonRep 2:keyEnciph 3:dataEnciph 4:keyAgree 5:keyCertSign 6:cRLSign 7:encipherOnly 8:decipherOnly

# Root CA: digitalSig + keyCertSign + cRLSign
ROOT_KU="true false false false false true true false false"
# Sub CA: keyCertSign + cRLSign only (no digitalSig per Phase 2 spec)
SUB_KU="false false false false false true true false false"

# 1. RootCAProd-ECC384-SHA384  (type=8, 10yr, ECDSA P-384, no pathLen constraint)
emit_profile "RootCAProd-ECC384-SHA384" 100 8 "3650d" "ECDSA" "secp384r1" "$ROOT_KU" "false" 0 "$CDP" "$AIA"

# 2. SubordCAProd-ECC384-SHA384 (type=2, 5yr, ECDSA P-384, pathLen=0)
emit_profile "SubordCAProd-ECC384-SHA384" 101 2 "1825d" "ECDSA" "secp384r1" "$SUB_KU" "true" 0 "$CDP" "$AIA"

# 3. RootCAPilot-ECC384-SHA384 (type=8, 90d, ECDSA P-384, no pathLen constraint)
emit_profile "RootCAPilot-ECC384-SHA384" 102 8 "90d" "ECDSA" "secp384r1" "$ROOT_KU" "false" 0 "$CDP" "$AIA"

# 4. SubordCAPilot-ECC384-SHA384 (type=2, 90d, ECDSA P-384, pathLen=0)
emit_profile "SubordCAPilot-ECC384-SHA384" 103 2 "90d" "ECDSA" "secp384r1" "$SUB_KU" "true" 0 "$CDP" "$AIA"

# 5. SubordCAPilot-RSA4096-SHA256 (type=2, 90d, RSA 4096, pathLen=0)
emit_profile "SubordCAPilot-RSA4096-SHA256" 104 2 "90d" "RSA" "4096" "$SUB_KU" "true" 0 "$CDP" "$AIA"

echo ""
echo "All 5 profiles generated in: $OUTDIR"
ls "$OUTDIR/"
