#!/bin/bash

OUTDIR=/home/family/media
OUTFILE=$OUTDIR/music.txt
MEDIATOMB_DATABASE=/var/lib/mediatomb/mediatomb.db

function generateDirWorker {
    sleep 120
    generateDirectory
}

function generateDirectory {
    TMPFILE=$(mktemp) && {
        OLDPATH=$(pwd)
        # Safe to use $TMPFILE in this block
        cd $OUTDIR/music/Collection; find -type f -print | LC_COLLATE="C" sort | grep '.mp3' | LC_COLLATE="C" sort > $TMPFILE
        cd $OLDPATH

        DIFFFILE=$(mktemp) && {
            diff --context=0 $OUTFILE $TMPFILE > $DIFFFILE
            if [ $? -ne 0 ]
            then
               NOTIFYTEXT=$(mktemp) && {

                  #prepare Mail MIME Header
                  echo "MIME-Version: 1.0" > $NOTIFYTEXT
                  echo "Content-type: multipart/mixed; boundary=abcdefgh" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  echo "--abcdefgh" >> $NOTIFYTEXT
                  echo "Content-type: text/plain" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT

                  #prepare Mail Content for Notify Text
                  echo "Change Notification of our Music Library" >> $NOTIFYTEXT
                  echo "   now $(wc -l $TMPFILE | sed 's/\([0-9]*\)\(.*\)/\1/') titles in collection" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  echo "   Change Set since $(stat -c %y $OUTFILE | sed 's/\([0-9\-]*\)\([ 0-9\:]*\)\(.*\)/\1\2/'):" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  echo "     Added:" >> $NOTIFYTEXT
                  cat $DIFFFILE | grep '^+ ' | sed -e 's/+ /        /' >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  echo "     Removed:" >> $NOTIFYTEXT
                  cat $DIFFFILE | grep '^- ' | sed -e 's/- /        /' >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT

                  echo "" >> $NOTIFYTEXT
                  echo "regards Andreas" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT

                  echo "--abcdefgh" >> $NOTIFYTEXT
                  echo "Content-Transfer-Encoding: base64" >> $NOTIFYTEXT
                  echo "Content-Type: application/octet-stream; name=music.txt" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT

                  #Unix2DOS; remove '.\'
                  sed -e 's/$/\r/' -e 's/.\///' $TMPFILE | base64 >> $NOTIFYTEXT

                  echo "" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT

                  echo "--abcdefgh" >> $NOTIFYTEXT
                  echo "Content-Transfer-Encoding: base64" >> $NOTIFYTEXT
                  echo "Content-Type: application/octet-stream; name=music.pdf" >> $NOTIFYTEXT
                  echo "" >> $NOTIFYTEXT
                  $(dirname $0)/musicDirPDF.sh $OUTDIR $MEDIATOMB_DATABASE
                  base64 ${OUTDIR}/music.pdf >> $NOTIFYTEXT

                  # send $NOTIFYTEXT via e-mail
                  cat  $(dirname $0)/musicDirHeader.txt $NOTIFYTEXT | /usr/lib/sendmail -t

                  #just for debugging purpose!!
                  #cat $NOTIFYTEXT
                  rm -f $NOTIFYTEXT

                  #after Mail Transmission - we make our new Listing the present one
                  cp $TMPFILE $OUTFILE
               }

            else
               echo "No Change"
            fi
            rm -f $DIFFFILE
        }
        rm -f $TMPFILE
    }
}

generateDirWorker&
