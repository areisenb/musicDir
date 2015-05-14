#!/usr/bin/perl

use strict;
use Getopt::Long;
use MP3::Tag;
use URI::Escape;
#use HTML::Entities;

# I cannot get these two working
#use TeX::Encode;
#use Encode;
  
my (%currEnvir);


########
# Usage
########
sub Usage {
  printf ("$0 <options> OutputFile\n");
  printf ("  options:\n");
  printf ("    --help:    this output\n");
  printf ("    --verbose: verbose level - up to 3\n");
  printf ("    --file:    input file - otherwise stdin\n");
  printf ('  execute: sqlite3 mediatomb.db \'select metadata,location \\'."\n");
  printf ('               from mt_cds_object \\'."\n");
  printf ('              where (upnp_class="object.item.audioItem.musicTrack") \\'."\n");
  printf ('             order by location\' >media.txt'."\n");
  printf ("   to generate appropiate input file\n");
  exit;
}

########
# Command Line Parsing
########
sub HandleCommandLine {
    my ($cmdLineResult, $strInFile, $bHelp, $nVerbose, $numArgs);
    my (%envir);

    $strInFile="";
    $bHelp=0;
    $nVerbose=0;
    Getopt::Long::Configure ("bundling");
    $cmdLineResult = GetOptions ('file=s' => \$strInFile,
                                 'f=s' => \$strInFile,
                                 'help' => \$bHelp,
                                 'h' => \$bHelp,
                                 'verbose+' =>\$nVerbose,
                                 'v+' =>\$nVerbose);

    $numArgs = @ARGV + 1;

    ($cmdLineResult >0 && $numArgs==2 && $bHelp==0) || Usage;
    
    $envir{nVerbLevel} = $nVerbose;
    $envir{strInFile} = $strInFile;
    $envir{strOutFile} = $ARGV[0];

    return(%envir);
}

########
# Parsing of Metadata
########
sub LogOut  {
   my ($nLogLevel, $strText) = @_;
   if ($nLogLevel <= ($currEnvir{nVerbLevel})) {
      print STDERR $strText;
   }
}

########
# Parsing of Metadata
########
sub ParseMetadata  {
   my ($strIn) = $_[0];
   my ($pastrAlbum) = $_[1];
   my ($panYear) = $_[2];
   my ($pastrArtist) = $_[3];
   my ($panTrackNo) = $_[4];
   my ($pastrTitle) = $_[5];
   my ($title, $artist, $album, $date, $genre, $trackNo) = "";
   my ($dc) = 0;
   my (@listIn) = split ('&', $strIn);
   my (@listElement, @aRest);
   
   foreach (@listIn) {
      @listElement = split ('=', $_);
      if (@listElement[0] =~ /dc%3Atitle/) {
         $title = @listElement[1];
         $dc=1;
      }
      if (@listElement[0] =~ /upnp%3Aartist/) {
         $artist = @listElement[1];
         $dc=1;
      }
      if (@listElement[0] =~ /upnp%3Aalbum/) {
         $album = @listElement[1];
         $dc=1;
      }
      if (@listElement[0] =~ /dc%3Adate/) {
         ($date, @aRest) =  split ('-', @listElement[1]);
         $dc=1;
      }
      if (@listElement[0] =~ /upnp%3Agenre/) {
         $genre = @listElement[1];
         $dc=1;
      }
      if (@listElement[0] =~ /upnp%3AoriginalTrackNumber/) {
         $trackNo = 0 + @listElement[1];
         $dc=1;
      }
      if ($dc == 0) {
         LogOut (0, "error: Name ".@listElement[0]." unknown\n");
      }
   }
   LogOut (2, sprintf ("    %02d - %s\n", $trackNo, $title));
   LogOut (2, "    $date, $album, $genre, $artist\n");
   push (@$pastrAlbum, $album);
   push (@$pastrArtist, $artist);
   push (@$panYear, $date+0);
   push (@$panTrackNo, $trackNo);
   push (@$pastrTitle, $title);
   if (@$pastrAlbum[$#$pastrAlbum-1].@$panYear[$#$panYear-1] eq $album.($date+0)) {
      return 0;
   } else {
      return 1;
   }
}

########
# Parsing of File Name
########
sub ParseFilename  {
   my ($strIn) = @_[0];
   $strIn =~ /(F)(.*)/;
   return $2;
}

########
# converts the ID3 POPM Rating info to 0..5 stars
########
sub POPMRating2Stars {
    # http://wiki.xbmc.org/index.php?title=Adding_music_to_the_library
    # 0
    # 1       * This is a special case for Windows Media Player
    # 2-8
    # 9-49    *
    # 50-113  **
    # 114-167 ***
    # 168-218 ****
    # 219-255 ***** 
    my ($nRating) = $_[0];
    
    if ($nRating > 237) { return (5); }
    if ($nRating > 218) { return (4.5); }
    if ($nRating > 193) { return (4); }
    if ($nRating > 167) { return (3.5); }
    if ($nRating > 140) { return (4); }
    if ($nRating > 113) { return (2.5); }
    if ($nRating > 81) { return (2); }
    if ($nRating > 49) { return (1.5); }
    if ($nRating > 29) { return (1); } 
    if ($nRating > 8) { return (0.5); }
    if ($nRating == 1) { return (1); }
}

########
# Parse some additional data from the original mp3 file
########
sub ParseMetadataFromID3  {
    my ($strMP3File) = $_[0];
    my ($pafRating) = $_[1];
    my ($panTrackLen) = $_[2];
    my ($mp3, $info, @info, @rest);
    my ($nTrackLen, $fRating);
    
    $nTrackLen = undef;
    $fRating = undef;
    
    $mp3 = MP3::Tag->new($strMP3File);
    if (defined ($mp3)) {
        $mp3->get_tags ();
        if (exists $mp3->{ID3v2}) {
            ($info, @rest) = $mp3->{ID3v2}->get_frame("TLEN");
            if (defined ($info)) {
               $nTrackLen = $info / 1000;
            } else {
               LogOut (0, "Warning: File \'$strMP3File\' does not contain  ID3v2 'TLEN' Tag\n");
            }
            @info = $mp3->{ID3v2}->get_frame("POPM");
            if (defined (@info)) {
               if (ref (@info[0])) {
                   my (%hinfo) = %{@info[0]};
                   my ($nRating) = $hinfo{Rating};
                   if (defined ($nRating)) {
                       $fRating = POPMRating2Stars ($nRating);
                       printf ("Rating: %s (%d)\n", $fRating, $nRating);
                   } else {
                       LogOut (0, "Warning: File \'$strMP3File\' ".
                                  "contains ID3v2 'POPM' Tag without 'Rating' field\n");
                   }
               } else {
                   LogOut (0, "Warning: File \'$strMP3File\' ".
                              "contains ID3v2 'POPM' Tag without additional info\n");
               }
            } else {
               LogOut (0, "Warning: File \'$strMP3File\' does not contain  ID3v2 'POPM' Tag\n");
            }
        } else {
            LogOut (0, "Notice: File \'$strMP3File\' does not contain any ID3v2 Tag\n");
        }
        $mp3->close();
    } else { 
        LogOut (0, "Warning: File \'$strMP3File\' invalid\n");
    }
    push (@$panTrackLen, $nTrackLen);
    push (@$pafRating, $fRating);
}

########
# Entire Line Parsing
########
sub ParseDatafromLine  {
   my ($strInLine) = @_[0];
   my ($pastrAlbum) = $_[1];
   my ($panYear) = $_[2];
   my ($panTrackNo) = $_[3];
   my ($pastrTitle) = $_[4];
   my ($pastrArtist) = $_[5];
   my ($pastrFileName) = $_[6];
   my ($pafRating) = $_[7];
   my ($panTrackLen) = $_[8];
   my ($strFileName, $bNewAlbum);
   
   #temporary only
   my ($nPopularity, $strTrackLen);
   
   my ($strMetaData, $strLocation, @aRest) = split('\|', $strInLine);
   $bNewAlbum = ParseMetadata ($strMetaData, $pastrAlbum, $panYear, 
                      $pastrArtist, $panTrackNo, $pastrTitle);
   $strFileName = ParseFilename ($strLocation);
   LogOut (2, "File: ".$strFileName."\n");
   push (@$pastrFileName, $strFileName);
   ParseMetadataFromID3 ($strFileName, $pafRating, $panTrackLen);
   return $bNewAlbum;
}

########
# Generate Cover File from ID3 tags
########
sub GenCoverFile {
    my ($strMP3File) = $_[0];
    my ($strOutDir) = $_[1];
    my ($nLineNumber) = $_[2];
    my ($mp3, @info, $strDestFile);
    $strDestFile = undef;
    
    $mp3 = MP3::Tag->new($strMP3File);
    if (defined ($mp3)) {
        $mp3->get_tags ();
        if (exists $mp3->{ID3v2}) {
            @info = $mp3->{ID3v2}->get_frame("APIC");
            if (defined (@info)) {
               if (ref (@info[0])) {
                   my (%hinfo) = %{@info[0]};
                   my ($imgData) = $hinfo{'_Data'};
                   my ($strMimeType) = $hinfo {'MIME type'};                   
                   if (defined ($imgData) && defined ($strMimeType)) {
                       if (!(-d $strOutDir)) {
                           #let's just create the dir, if it does not exist
                           mkdir ($strOutDir);
                       }
                       # Create destination path w. img mimetype suffix
                       my ($m1, $m2) = split(/\//, $strMimeType);
                       $strDestFile = sprintf ("%s/%06d.%s", $strOutDir, $nLineNumber, $m2);
                       # Write image data to file
                       if (open(ARTWORK, ">$strDestFile")) {
                           binmode(ARTWORK);
                           print ARTWORK $imgData;
                           close(ARTWORK);
                       } else {
                           $strDestFile = undef;
                           LogOut (0, "Error: cannot write File \'$strDestFile\'\n");
                       }
                   } else {
                       LogOut (0, "Warning: File \'$strMP3File\' ".
                                  "contains ID3v2 'APIC' Tag without '_Data', 'MIME type' field\n");
                   }
               } else {
                   LogOut (0, "Warning: File \'$strMP3File\' ".
                              "contains ID3v2 'APIC' Tag without additional info\n");
               }
            } else {
               LogOut (0, "Warning: File \'$strMP3File\' does not contain  ID3v2 'APIC' Tag\n");
            }
        } else {
            LogOut (2, "Notice: File \'$strMP3File\' does not contain any ID3v2 Tag\n");
        }
        $mp3->close();
    } else { 
        LogOut (2, "Warning: File \'$strMP3File\' invalid\n");
    }
    return ($strDestFile);
}

########
# Generate Album Artist from ID3 tags
########
# either take it from the file - if that does not work (no File, no ID3, no Album Artist
#   take the one provided with the 2nd argument as the Album Artist
sub GenAlbumArtistFromID3 {
    my ($strMP3File) = $_[0];
    my ($strDefaultAlbumArtist) = $_[1];
    my ($mp3, $info, @rest);
    
    $mp3 = MP3::Tag->new($strMP3File);
    if (defined ($mp3)) {
        $mp3->get_tags ();
        if (exists $mp3->{ID3v2}) {
            ($info, @rest) = $mp3->{ID3v2}->get_frame("TPE2");
            if (!defined ($info)) {
               LogOut (2, "Notice: File \'$strMP3File\' does not contain  ID3v2 'TPE2' Tag\n");
            }
        } else {
            LogOut (2, "Notice: File \'$strMP3File\' does not contain any ID3v2 Tag\n");
        }
        $mp3->close();
    } else { 
        LogOut (2, "Warning: File \'$strMP3File\' invalid\n");
    }
    if (defined ($info)) {
        return $info;
    } else {
        LogOut (2, "   Taking default: $strDefaultAlbumArtist\n");
        return $strDefaultAlbumArtist;
    }
}

########
# Artist Outputting 
########
sub Artist2Latex {
   my ($OutFile) = $_[0];
   my ($strAlbumArtist) = $_[1]; 
   $strAlbumArtist = uri_unescape ($strAlbumArtist);

   LogOut (0, "AlbumArtist: $strAlbumArtist\n");
   printf $OutFile "\\addcontentsline{toc}{section}{%s}\n", 
       Conv2LatexFont ($strAlbumArtist);
   printf $OutFile "\\section*{%s}\n", 
       Conv2LatexFont ($strAlbumArtist);
}

########
# Album Outputting 
########
sub Album2Latex  {
   my ($OutFile) = $_[0];
   my ($strAlbum) = $_[1];
   my ($strAlbumArtist) = $_[2];
   my ($strCoverFileName) = $_[3];
   my ($nTrackCount) = $_[4];
   my ($nYear) = $_[5];
   my ($panTrackNo) = $_[6];
   my ($pastrTitle) = $_[7];
   my ($pastrArtist) = $_[8];
   my ($pafRating) = $_[9];
   my ($panTrackLen) = $_[10];
   my ($phStatistics) = $_[11];   
   
   $strAlbum = uri_unescape ($strAlbum);
   $strAlbumArtist = uri_unescape ($strAlbumArtist);
   
   LogOut (0, "Album: $strAlbum; AlbumArtist: $strAlbumArtist\n");
   printf $OutFile "\\addcontentsline{toc}{subsection}{%s}\n", 
       Conv2LatexFont ($strAlbum);
   printf $OutFile "\\subsection*{%s (%d)}\n", 
       Conv2LatexFont ($strAlbum), $nYear;
   
   
   print $OutFile Medium2LatexString ($strAlbumArtist, 
                        $strCoverFileName, $nTrackCount,
                        $panTrackNo, $pastrTitle, 
                        $pastrArtist, $pafRating, $panTrackLen, 
                        $phStatistics);
   $$phStatistics { nAlbumCount } += 1;
}

########
# Latex Medium (1CD) Outputting 
########
sub Medium2LatexString {
   my ($strAlbumArtist) = $_[0];
   my ($strCoverFileName) = $_[1];
   my ($nTrackCount) = $_[2];
   my ($panTrackNo) = $_[3];
   my ($pastrTitle) = $_[4];
   my ($pastrArtist) = $_[5];
   my ($pafRating) = $_[6];
   my ($panTrackLen) = $_[7];
   my ($phStatistics) = $_[8];   
   

   my ($strArtist, $nTrackNo, $nOldTrackNo, $strTrackNo, $strTitle);
   my ($fRating, $nTrackLen);
   my ($strResult);
   my ($nLineCount) = 0;
   my ($i);
   
   $$phStatistics { nMediaCount } += 1;
   
   $strResult = "\\begin{tabular}{|r l l r c|}\n\\hline\n";

   for ($i=0;$i < $nTrackCount;$i++) {
      $nOldTrackNo = $nTrackNo;
      $nTrackNo = shift (@$panTrackNo);
      if ($nTrackNo > 0) {
          $strTrackNo = sprintf ("%d", $nTrackNo);
      } else {
          $strTrackNo = "";
      }
      if (defined ($nOldTrackNo)) {
          if ($nOldTrackNo > $nTrackNo) {
              #within the same album but new Medium
              unshift (@$panTrackNo, $nTrackNo);
              last;
          }
      }
      $strTitle = uri_unescape (shift (@$pastrTitle));
      LogOut(1, sprintf ("  %02d-%s", $nTrackNo, $strTitle));
      $strArtist = uri_unescape (shift (@$pastrArtist));

      if ($strArtist ne $strAlbumArtist) {
          LogOut (1, " ($strArtist)\n");
          if ((length ($strTitle) + length ($strArtist)) < 30) {
              $strTitle = Conv2LatexFont ($strTitle)."\\textit{ - ".Conv2LatexFont ($strArtist)."}";
              $strArtist = undef;
          } else {
              $strTitle = Conv2LatexFont ($strTitle);
              $strArtist = Conv2LatexFont ($strArtist);
          }
      } else {
          LogOut (1, "\n");
          $strArtist = undef;
          $strTitle = Conv2LatexFont ($strTitle);
      }
      
      $nLineCount++;
      $fRating = shift (@$pafRating);
      $nTrackLen = shift (@$panTrackLen);
      $strResult .= sprintf ("%s & %s & \\includegraphics[scale=0.5]{%s} & ", 
                        $strTrackNo, $strTitle,
                        Rating2Graphics ($fRating));
      if (defined ($nTrackLen)) {
          $strResult .= sprintf ("%d:%02d", , $nTrackLen/60, $nTrackLen%60);
      }
      $strResult .= " & ";
      
      if (($nLineCount==1) && (defined ($strCoverFileName))) {
          $strResult .= "\\multirow{9}{*}{\\includegraphics[width=3cm]{".$strCoverFileName."}}";
      }
      $strResult .= "\\\\\n";

      # Statistic gathering
      $$phStatistics { nTrackCount } += 1;
      $$phStatistics { nTrackLen } += $nTrackLen;
      if (defined $fRating) {
        $$phStatistics { Rating } { sprintf ("%02d", 10*$fRating) } { cnt } += 1;
        $$phStatistics { Rating } { sprintf ("%02d", 10*$fRating) } { len } += $nTrackLen;
      } else { 
        $$phStatistics { Rating } { "undef" } { cnt } += 1;
        $$phStatistics { Rating } { "undef" } { len } += $nTrackLen;
      }
      if (defined ($nTrackLen)) {
          if ($nTrackLen > (10*60)) {
              $$phStatistics { TrkLen } { 10 } += 1;
          } else {
              if ($nTrackLen > (7*60)) {
                  $$phStatistics { TrkLen } { 7 } += 1;
          } else {
              if ($nTrackLen > (5*60)) {
                  $$phStatistics { TrkLen } { 5 } += 1;
          } else {
              if ($nTrackLen > (3*60)) {
                  $$phStatistics { TrkLen } { 3 } += 1;
          } else {
              if ($nTrackLen > (1*60)) {
                  $$phStatistics { TrkLen } { 1 } += 1;
          } else {
                  $$phStatistics { TrkLen } { 0 } += 1;
          }
          }
          }
          }
          }
      } else {
           $$phStatistics { TrkLen } { undef } += 1;
      }
              
      if (defined ($strArtist)) {
          $strResult .= sprintf ("& \\textit{%s} & & & \\\\\n", $strArtist);
      } 
   }   
   for (;$nLineCount<9; $nLineCount++) {
      $strResult .= "& & & & \\\\\n";
   }
   
   $strResult .= '\hline'."\n".'\end{tabular}'."\n";
   $nTrackCount -= $i;
   if ($nTrackCount > 0) {
      $strResult .= "\n".Medium2LatexString ($strAlbumArtist, 
                        $strCoverFileName, $nTrackCount,
                        $panTrackNo, $pastrTitle, 
                        $pastrArtist, $pafRating, $panTrackLen,
                        $phStatistics);
   }
   return ($strResult);
}

########
# Latex Header Outputting 
########
sub Header2Latex  {
   my ($OutFile) = $_[0];
   print $OutFile "\\documentclass[a4paper]{article}\n";
   print $OutFile "\\usepackage[pdftex]{graphicx}\n";
   
   print $OutFile "\\setlength{\\topmargin}{-1cm}\n";
   print $OutFile "\\setlength{\\headheight}{0cm}\n";
   print $OutFile "\\setlength{\\headsep}{0cm}\n";
   print $OutFile "\\setlength{\\textheight}{26cm}\n";

   print $OutFile "\\setlength{\\evensidemargin}{0cm}\n";
   print $OutFile "\\setlength{\\oddsidemargin}{0cm}\n";
   print $OutFile "\\setlength{\\textwidth}{16cm}\n";

   print $OutFile "\\setlength{\\parindent}{0pt}\n";

   print $OutFile "\\begin{document}\n";
}

########
# Latex Footer Outputting 
########
sub Footer2Latex  {
   my ($OutFile) = $_[0];
   print $OutFile "\\end{document}\n";
}

########
# Latex Font Conversion
########
sub Conv2LatexFont {
   my ($str) = $_[0];
   # why this does not work is not obvious...
   #$str = encode('latex', $str);   
   #return ($str);
   
   $str =~ s/&/\\&/g;
   $str =~ s/\$/\\\$/g;
   $str =~ s/_/ /g;
   $str =~ s/#/\\#/g;
   #Umlaute (all started by c3)
   #German 
   #-----------
   # 9f ß
   $str =~ s/\xc3\x9f/\\ss{}/g;
   # a4 ä
   $str =~ s/\xc3\xa4/\\"a/g;
   # b6 ö
   $str =~ s/\xc3\xb6/\\"o/g;
   # bc Ü
   $str =~ s/\xc3\x9c/\\"U/g;
   # bc ü
   $str =~ s/\xc3\xbc/\\"u/g;
   #Italian
   #------------
   # à è é ì ò ù
   # \‘a \‘e \'e \‘i \‘o \‘u
   # a0 a mit Strich li oben nach re unten
   $str =~ s/\xc3\xa0/\\`a/g;
   # a8 e mit Strich li oben nach re unten
   $str =~ s/\xc3\xa8/\\`e/g;
   # a9 e mit Strich li unten nach re oben
   $str =~ s/\xc3\xa9/\\'e/g;
   # b9 u mit Strich li oben nach re unten
   $str =~ s/\xc3\xb9/\\`u/g;
   #Espania
   #------------
   # 81 A mit strich li unten nach re oben
   $str =~ s/\xc3\x81/\\'A/g;
   # 83 a mit strich li unten nach re oben
   $str =~ s/\xc3\x83/\\'a/g;
   # a1 a mit strich li unten nach re oben - unlogisch - 2 mal das gleiche?
   $str =~ s/\xc3\xa1/\\'a/g;
   # ad i mit Strich li unten nach re oben (anstelle des Punktes)
   $str =~ s/\xc3\xad/\\'i/g;
   # b3 o mit Strich li unten nach re oben
   $str =~ s/\xc3\xb3/\\'o/g;
   # b1 n mit tilde drauf
   $str =~ s/\xc3\xb1/\\~n/g;
   # ba u mit Strich li unten nach re oben
   $str =~ s/\xc3\xba/\\'u/g;
   
   return ($str);
}

########
# Convert Rating to Image File Name
########
sub Rating2Graphics  {
    my ($fRating) = $_[0];
    if (defined $fRating) {
        return (sprintf ("icons/rating%02d.png", 10*$fRating));
    }
    return ("icons/ratingNO.png");
}

########
# Seconds to String conversion
########
sub Seconds2String {
    use integer;
    my ($nSeconds) = $_[0];
    my ($nDays, $nHours, $nMins);
    my ($strOut);
    
    $nDays = $nSeconds / (60*60*24);
    if ($nDays > 0) {
        $nSeconds %= (60*60*24);
        $strOut = sprintf ("%dd %02dh %02dm %02ds", 
            $nDays, $nSeconds/3600, $nSeconds/60-60*($nSeconds/3600), 
            $nSeconds%60, 
            $nSeconds + $nDays*(60*60*24));
    } else {
       $nHours = $nSeconds / (60*60);
       if ($nHours > 0) {
           $nSeconds %= (60*60);
           $strOut = sprintf ("%d:%02d:%02d",
             $nHours, $nSeconds / 60, $nSeconds % 60,
             $nSeconds + $nHours*(60*60));
       } else {
           $strOut = sprintf ("%d:%02d", $nSeconds/60, $nSeconds%60, $nSeconds);
       }
    }
    
    return ($strOut);
}
    
########
# Reduce Array to Last Item 
########
sub Reduce2LastItem  {
    my (@astr) = @{$_[0]};
    my ($str) = @astr [$#astr];
    return ($str);
}

########
# Initialise statistics
########
sub InitStatistics  {
    my ($phStatistics) = $_[0];
    $$phStatistics { nTrackLen } = 0;
    $$phStatistics { nTrackCount } = 0;
    $$phStatistics { nMediaCount } = 0;
    $$phStatistics { nAlbumCount } = 0;
    $$phStatistics { nArtistCount } = 0;
    
    
    $$phStatistics { Rating } { 50 } { cnt } = 0;
    $$phStatistics { Rating } { 45 } { cnt } = 0;
    $$phStatistics { Rating } { 40 } { cnt } = 0;
    $$phStatistics { Rating } { 35 } { cnt } = 0;
    $$phStatistics { Rating } { 30 } { cnt } = 0;
    $$phStatistics { Rating } { 25 } { cnt } = 0;
    $$phStatistics { Rating } { 20 } { cnt } = 0;
    $$phStatistics { Rating } { 15 } { cnt } = 0;
    $$phStatistics { Rating } { 10 } { cnt } = 0;
    $$phStatistics { Rating } { 05 } { cnt } = 0;
    $$phStatistics { Rating } { 00 } { cnt } = 0;
    $$phStatistics { Rating } { undef } { cnt } = 0;
    
    $$phStatistics { Rating } { 50 } { len } = 0;
    $$phStatistics { Rating } { 45 } { len } = 0;
    $$phStatistics { Rating } { 40 } { len } = 0;
    $$phStatistics { Rating } { 35 } { len } = 0;
    $$phStatistics { Rating } { 30 } { len } = 0;
    $$phStatistics { Rating } { 25 } { len } = 0;
    $$phStatistics { Rating } { 20 } { len } = 0;
    $$phStatistics { Rating } { 15 } { len } = 0;
    $$phStatistics { Rating } { 10 } { len } = 0;
    $$phStatistics { Rating } { 05 } { len } = 0;
    $$phStatistics { Rating } { 00 } { len } = 0;
    $$phStatistics { Rating } { undef } { len } = 0;

    $$phStatistics { TrkLen } { 10 } = 0;
    $$phStatistics { TrkLen } { 7 } = 0;
    $$phStatistics { TrkLen } { 5 } = 0;
    $$phStatistics { TrkLen } { 3 } = 0;
    $$phStatistics { TrkLen } { 1 } = 0;
    $$phStatistics { TrkLen } { 0 } = 0;
    $$phStatistics { TrkLen } { undef } = 0;
    
}

########
# Initialise statistics
########
sub Statistics2Latex  {
    my ($OutFile) = $_[0];
    my (%hStatistics) = %{$_[1]};

    
    LogOut (1, "**** Statistik\n");
    print $OutFile "\\newpage\n\\appendix\n";
    print $OutFile "\\section{Statistik}\n";
   
    LogOut (1, " Artist Count: ".$hStatistics{nArtistCount}."\n");    
    LogOut (1, " Album Count:  ".$hStatistics{nAlbumCount}."\n");    
    LogOut (1, " Media Count:  ".$hStatistics{nMediaCount}."\n");    
    LogOut (1, " Track Count:  ".$hStatistics{nTrackCount}."\n");  
    LogOut (1, " Track Len:    ".Seconds2String ($hStatistics{nTrackLen})."\n");
    print $OutFile "\\subsection{Allgemein}\n";
    print $OutFile "\\begin{tabular}{|l | r|}\n\\hline\n";
    print $OutFile "K\\\"unstler & ".$hStatistics{nArtistCount}."\\\\\n";
    printf $OutFile "\\hline\n";
    print $OutFile "Alben & ".$hStatistics{nAlbumCount}."\\\\\n";
    printf $OutFile "\\hline\n";
    print $OutFile "Medien & ".$hStatistics{nMediaCount}."\\\\\n";
    printf $OutFile "\\hline\n";
    print $OutFile "Musikst\\\"ucke & ".$hStatistics{nTrackCount}."\\\\\n";
    printf $OutFile "\\hline\n";
    print $OutFile "Dauer & ".Seconds2String ($hStatistics{nTrackLen})."\\\\\n";
    print $OutFile '\hline'."\n".'\end{tabular}'."\n";

   
    LogOut (1, " *****         ".$hStatistics{Rating}{50}{cnt}." ".Seconds2String ($hStatistics{Rating}{50}{len})."\n");    
    LogOut (1, " ****.         ".$hStatistics{Rating}{45}{cnt}." ".Seconds2String ($hStatistics{Rating}{45}{len})."\n");    
    LogOut (1, " ****          ".$hStatistics{Rating}{40}{cnt}." ".Seconds2String ($hStatistics{Rating}{40}{len})."\n");    
    LogOut (1, " ***.          ".$hStatistics{Rating}{35}{cnt}." ".Seconds2String ($hStatistics{Rating}{35}{len})."\n");    
    LogOut (1, " ***           ".$hStatistics{Rating}{30}{cnt}." ".Seconds2String ($hStatistics{Rating}{30}{len})."\n");    
    LogOut (1, " **.           ".$hStatistics{Rating}{25}{cnt}." ".Seconds2String ($hStatistics{Rating}{25}{len})."\n");    
    LogOut (1, " **            ".$hStatistics{Rating}{20}{cnt}." ".Seconds2String ($hStatistics{Rating}{20}{len})."\n");    
    LogOut (1, " *.            ".$hStatistics{Rating}{15}{cnt}." ".Seconds2String ($hStatistics{Rating}{15}{len})."\n");    
    LogOut (1, " *             ".$hStatistics{Rating}{10}{cnt}." ".Seconds2String ($hStatistics{Rating}{10}{len})."\n");    
    LogOut (1, " .             ".$hStatistics{Rating}{05}{cnt}." ".Seconds2String ($hStatistics{Rating}{05}{len})."\n");    
    LogOut (1, "               ".$hStatistics{Rating}{00}{cnt}." ".Seconds2String ($hStatistics{Rating}{00}{len})."\n");    
    LogOut (1, " undef         ".$hStatistics{Rating}{undef}{cnt}." ".Seconds2String ($hStatistics{Rating}{undef}{len})."\n");    
    printf $OutFile "\\subsection{Bewertungen}\n";
    printf $OutFile "\\begin{tabular}{|l | r| r|}\n\\hline\n";
    printf $OutFile "Bewertung & Anzahl & L\\\"ange \\\\\n";
    printf $OutFile "\\hline\n";
    for (my ($f)=5;$f >= 0.0; $f-=0.5) {
        my ($strIdx) = sprintf ("%02d", 10*$f);
        printf $OutFile "\\includegraphics[scale=0.5]{%s} & %d & %s\\\\\n", 
                  Rating2Graphics ($f),         
                  $hStatistics{Rating}{$strIdx}{cnt},
                  Seconds2String ($hStatistics{Rating}{$strIdx}{len});
        printf $OutFile "\\hline\n";
    }
    printf $OutFile "\\includegraphics[scale=0.5]{%s} & %d & %s\\\\\n", 
              Rating2Graphics (undef),         
              $hStatistics{Rating}{undef}{cnt},
              Seconds2String ($hStatistics{Rating}{undef}{len});
    print $OutFile '\hline'."\n".'\end{tabular}'."\n";
    
    LogOut (1, "Length:\n");
    LogOut (1, " > 10min: ".$hStatistics {TrkLen}{10}."\n");
    LogOut (1, "  > 7min: ".$hStatistics {TrkLen}{7}."\n");
    LogOut (1, "  > 5min: ".$hStatistics {TrkLen}{5}."\n");
    LogOut (1, "  > 3min: ".$hStatistics {TrkLen}{3}."\n");
    LogOut (1, "  > 1min: ".$hStatistics {TrkLen}{1}."\n");
    LogOut (1, "  > 0min: ".$hStatistics {TrkLen}{0}."\n");
    LogOut (1, "  undef:  ".$hStatistics {TrkLen}{undef}."\n");
    print $OutFile "\\subsection{L\\\"angen}\n";
    print $OutFile "\\begin{tabular}{|r | r|}\n\\hline\n";
    print $OutFile "L\\\"ange & Anzahl \\\\\n";
    printf $OutFile "\\hline\n";
    print $OutFile "\\textgreater 10 min & ".$hStatistics {TrkLen}{10}."\\\\\n";
    print $OutFile "\\textgreater 7 min & ".$hStatistics {TrkLen}{7}."\\\\\n";
    print $OutFile "\\textgreater 5 min & ".$hStatistics {TrkLen}{5}."\\\\\n";
    print $OutFile "\\textgreater 3 min & ".$hStatistics {TrkLen}{3}."\\\\\n";
    print $OutFile "\\textgreater 1 min & ".$hStatistics {TrkLen}{1}."\\\\\n";
    print $OutFile "\\textgreater 0 min & ".$hStatistics {TrkLen}{0}."\\\\\n";
    print $OutFile "undefiniert & ".$hStatistics {TrkLen}{undef}."\\\\\n";
    print $OutFile '\hline'."\n".'\end{tabular}'."\n";
    
    
}

%currEnvir = HandleCommandLine;
LogOut (0, 'Generating \''.$currEnvir{strOutFile}.'\' ');

if ($currEnvir{strInFile}."_" ne "_") {
    LogOut (0,  'out of \''.$currEnvir{strInFile}.'\''."...\n");    
} else {
    LogOut (0, "from stdin ...\n");
}
LogOut (3, "Command Line Parameters\n");
foreach my $name (keys %currEnvir) {
      LogOut (3, "$name / ".$currEnvir{$name}."\n");
    }

open(INFILE, $currEnvir{strInFile} ) 
    || die "cannot open ".$currEnvir{strInFile}." for read\n";
open (OUTFILE, ">".$currEnvir{strOutFile} ) 
    || die "cannot open".$currEnvir{strOutFile}." for write\n";

my ($bNewAlbum, @astrAlbum, @anYear, @anTrackNo, @astrTitle, @astrArtist, @astrFileName);
my (@afRating, @anTrackLen);
my ($strCoverFileName, $nTrackCount, $strAlbumArtist, $nLineNumber);
my ($strOldAlbumArtist);
my (%hStatistics);

#Header2Latex (*OUTFILE);
$nLineNumber = 0;

InitStatistics (\%hStatistics);
$hStatistics {nArtistCount} = 0;

while (<INFILE>) {
   $nLineNumber ++;
   $bNewAlbum = ParseDatafromLine ( $_, \@astrAlbum, \@anYear,
                      \@anTrackNo, \@astrTitle, \@astrArtist, \@astrFileName,
                      \@afRating, \@anTrackLen );
   if ($bNewAlbum) {
      $nTrackCount = $#astrFileName; # last index already consists next album
      $strCoverFileName = GenCoverFile ($astrFileName[0], $currEnvir{strOutFile}.".d", $nLineNumber);
      $strAlbumArtist = GenAlbumArtistFromID3 ($astrFileName[0], $astrArtist[0]);
      if ((!defined ($strOldAlbumArtist)) || ($strOldAlbumArtist ne uri_unescape ($strAlbumArtist))) {
          LogOut (1, "Album Artist: ".$strAlbumArtist."\n");
          Artist2Latex (*OUTFILE, $strAlbumArtist);
          $strOldAlbumArtist = uri_unescape ($strAlbumArtist);
          $hStatistics { nArtistCount } += 1;
      }
      LogOut (1, "Album: ".$astrAlbum[0]." - Track Count: ".$nTrackCount."\n");
      Album2Latex (*OUTFILE, $astrAlbum[0], $strAlbumArtist, $strCoverFileName, 
           $nTrackCount, $anYear[0], 
           \@anTrackNo, \@astrTitle, \@astrArtist, \@afRating, \@anTrackLen,
           \%hStatistics );
      @astrFileName = Reduce2LastItem (\@astrFileName);
      @astrAlbum = Reduce2LastItem (\@astrAlbum);
      @anYear = Reduce2LastItem (\@anYear);
   }
}
$nLineNumber ++;
$nTrackCount = $#astrFileName+1;
$strCoverFileName = GenCoverFile ($astrFileName[0], $currEnvir{strOutFile}.".d", $nLineNumber);
$strAlbumArtist = GenAlbumArtistFromID3 ($astrFileName[0], $astrArtist[0]);
if ((!defined ($strOldAlbumArtist)) || ($strOldAlbumArtist ne $strAlbumArtist)) {
    LogOut (1, "Album Artist: ".$strAlbumArtist."\n");
    Artist2Latex (*OUTFILE, $strAlbumArtist);
    $strOldAlbumArtist = $strAlbumArtist;
    $hStatistics { nArtistCount } += 1;
}
LogOut (1, "Album: ".$astrAlbum[0]." - Track Count: ".$nTrackCount."\n");
Album2Latex (*OUTFILE, $astrAlbum[0], $strAlbumArtist, $strCoverFileName, 
     $nTrackCount, $anYear[0], 
     \@anTrackNo, \@astrTitle, \@astrArtist, \@afRating, \@anTrackLen,
     \%hStatistics );   

#Footer2Latex (*OUTFILE);

Statistics2Latex (*OUTFILE, \%hStatistics);
     

close (OUTFILE);
close (INFILE);


