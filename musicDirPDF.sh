#!/bin/bash

PDFDIRTAIL="/musicDirPDF.d"
LATEXSOURCE="$(dirname $0)$PDFDIRTAIL"
PDFDIRTARGET=$1
SQLITEFILE=$2
SQLITE_SEL_STRING='select metadata,location from mt_cds_object where (upnp_class="object.item.audioItem.musicTrack") order by location'

function cleanup {
  echo "Want to cleanup"
  rm -Rf "${PDFDIRTARGET}${PDFDIRTAIL}"
}

if [ ! -d $PDFDIRTARGET ] 
then
  echo "Directory $PDFDIRTARGET does not exist"
  cleanup
  exit
fi
#copy all the needed files into the out directory
cp -R $LATEXSOURCE $PDFDIRTARGET

if [ ! -f $SQLITEFILE ]
then
  echo "SQLite File $SQLITEFILE does not exist"
  cleanup
  exit
fi
#copy a snapshot of the SQLite Database
cp $SQLITEFILE "${PDFDIRTARGET}${PDFDIRTAIL}"

#now select the according records from the database
sqlite3 "${PDFDIRTARGET}${PDFDIRTAIL}/$(basename $SQLITEFILE)" "$SQLITE_SEL_STRING" >"${PDFDIRTARGET}${PDFDIRTAIL}/media.txt"

#generating the tex file in perl
$(dirname $0)/genDirFromDatabaseExport.pl -v -f ${PDFDIRTARGET}${PDFDIRTAIL}/media.txt ${PDFDIRTARGET}${PDFDIRTAIL}/media.tex

#generating the pdf File
pushd ${PDFDIRTARGET}${PDFDIRTAIL}
for (( i=0;i<3;i++)); do
    pdflatex ${PDFDIRTARGET}${PDFDIRTAIL}/music.tex
done 

#und zum Schluss noch in das "root" directory kopieren
mv ${PDFDIRTARGET}${PDFDIRTAIL}/music.pdf ..

popd

