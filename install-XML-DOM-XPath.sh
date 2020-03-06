#!/usr/bin/env bash

# XML::DOM::Path won't install without '--force' because of a broken test.
# 
# This script downloads the package, fixes the test, rewrites the source and 
# checksum files, and then does the (unforced) install
# 
# assumes CPAN can install in a suitable directory for the user who runs this
# script
#
# add the following to .bashrc for CPAN installs in the user's personal file space:
# 
#       PATH="$HOME/perl5/bin${PATH:+:${PATH}}"; export PATH;
#       PERL5LIB="$HOME/perl5/lib/perl5${PERL5LIB:+:${PERL5LIB}}"; export PERL5LIB;
#       PERL_LOCAL_LIB_ROOT="$HOME/perl5${PERL_LOCAL_LIB_ROOT:+:${PERL_LOCAL_LIB_ROOT}}"; export PERL_LOCAL_LIB_ROOT;
#       PERL_MB_OPT="--install_base \"$HOME/perl5\""; export PERL_MB_OPT;
#       PERL_MM_OPT="INSTALL_BASE=$HOME/perl5"; export PERL_MM_OPT;

TEMP_DIR=/tmp/`basename $0`-$$-temp
mkdir -p ${TEMP_DIR}

function Exit () {
   rm -r ${TEMP_DIR}
   exit $1
}

# download package from CPAN
perl -MCPAN -e 'get XML::DOM::XPath' > ${TEMP_DIR}/get.log 2>&1
get_exit=$?
if [ 0 -ne ${get_exit} ]; then
   cat ${TEMP_DIR}/get.log
   Exit ${get_exit} 
fi

# file files we need
gzipped_source_file=$(perl -ne 'm~Checksum for (/.*/XML\-DOM\-XPath\-[\d\.]+\.tar\.gz) ok~ && print $1' ${TEMP_DIR}/get.log)
if [[ -z ${gzipped_source_file} || ! -f ${gzipped_source_file} ]]; then
   echo "Couldn't find source file for XML::DOM::XPath"
   Exit 255
fi
package_name=$(basename $gzipped_source_file | sed -e 's/\.tar\.gz$//')
checksums_file=$(dirname $gzipped_source_file)/CHECKSUMS
if [[ -z ${checksums_file} || ! -f ${checksums_file} ]]; then
   echo "Couldn't find CHECKSUMS file for XML::DOM::XPath"
   Exit 255
fi

# tweak the problematic test file
mkdir -p ${TEMP_DIR}/extracted
cd ${TEMP_DIR}/extracted
tar xzf ${gzipped_source_file} || Exit $?
find . -name 'test_non_ascii.t' -exec sed -ire "s/use encoding 'utf8';/use utf8;/" {} \;

# make new gzipped source file, and get checksums
tar -cf ${package_name}.tar ${package_name}/  || Exit $?
md5_ungz=$(md5sum ${package_name}.tar | sed -e 's/ .*//')
sha256_ungz=$(sha256sum ${package_name}.tar | sed -e 's/ .*//')
gzip ${package_name}.tar || Exit $?
md5=$(md5sum ${package_name}.tar.gz | sed -e 's/ .*//')
sha256=$(sha256sum ${package_name}.tar.gz | sed -e 's/ .*//')
size=$(stat --printf="%s" ${package_name}.tar.gz)
mtime=$(date +'%Y-%m-%d')
# this is what needs to go into the CHECKSUMS file
checksum_block="
  '${package_name}.tar.gz' => {
    'md5' => '${md5}',
    'md5-ungz' => '${md5_ungz}',
    'mtime' => '${mtime}',
    'sha256' => '${sha256}',
    'sha256-ungz' => '${sha256_ungz}',
    'size' => ${size}
  },
"

# replace the original gzipped source file
mv ${package_name}.tar.gz ${gzipped_source_file}

# alter the original CHECKSUMS file
perl -we "\$r=0; while(<>){ \$r=1 if m/${package_name}\.tar\.gz/; print unless \$r; if(\$r && m/\}/){print \"${checksum_block}\n\"; \$r=0} }" ${checksums_file} > temp_checksum_file
if [[ 0 -ne $? || -z temp_checksum_file ]]; then
   echo "Failed to create new checksum file"
   Exit 255
fi
mv temp_checksum_file ${checksums_file}

# install the package using the altered source & checksums files
perl -MCPAN -e 'install XML::DOM::XPath' > ${TEMP_DIR}/install.log 2>&1
install_exit=$?
cat ${TEMP_DIR}/install.log
if [ 0 -ne ${install_exit} ]; then
   echo
   echo "Sorry, the install is still failing."
   Exit ${install_exit} 
fi

Exit
