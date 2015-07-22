#! /usr/bin/perl -w

# adapted version for parallel scoring of mbot rules
# example
# ./score-parallel-mbot.perl 8 "gsort --batch-size=253" ./score_mbot ./extract.2.sorted.gz ./lex.f2e ./mbot-rule-table.2.half.f2e  --GoodTuring ./mbot-rule-table.2.coc 0
# ./score-parallel-mbot.perl 8 "gsort --batch-size=253" ./score_mbot ./extract.2.inv.sorted.gz ./lex.e2f /mbot-rule-table.2.half.e2f  --Inverse 1

use strict;
use File::Basename;

sub RunFork($);
sub systemCheck($);
sub GetSourcePhrase($);
sub NumStr($);
sub CutContextFile($$$);

my $EXTRACT_SPLIT_LINES = 10000000;

print STDERR "Started ".localtime() ."\n";

my $numParallel	= $ARGV[0];
$numParallel = 1 if $numParallel < 1;

my $sortCmd			= $ARGV[1];
my $scoreCmd		= $ARGV[2];
my $extractFile = $ARGV[3]; # 1st arg of extract argument
my $lexFile 		= $ARGV[4];
my $ptHalf 			= $ARGV[5]; # output

my $otherExtractArgs= "";
for (my $i = 5; $i < $#ARGV; ++$i) {
  $otherExtractArgs .= $ARGV[$i] ." ";
}
#$scoreCmd $extractFile $lexFile $ptHalf $otherExtractArgs

my $doSort			= $ARGV[$#ARGV]; # last arg

my $TMPDIR=dirname($ptHalf)  ."/tmp.$$";
mkdir $TMPDIR;

my $cmd;

my $fileCount = 0;
if ($numParallel <= 1) {
  # don't do parallel. Just link the extract file into place
  $cmd = "ln -s $extractFile $TMPDIR/extract.0.gz";
  print STDERR "$cmd \n";
  systemCheck($cmd);

  $fileCount = 1;
} else {
  # cut up extract file into smaller mini-extract files.
	if ($extractFile =~ /\.gz$/) {
		open(IN, "gunzip -c $extractFile |") || die "can't open pipe to $extractFile";
	}
	else {
		open(IN, $extractFile) || die "can't open $extractFile";
	}

  my $filePath  = "$TMPDIR/extract.$fileCount.gz";
	open (OUT, "| gzip -c > $filePath") or die "error starting gzip $!";

	my $lineCount = 0;
	my $line;
	my $prevSourcePhrase = "";
	while ($line=<IN>) {
		chomp($line);
		++$lineCount;

		if ($lineCount > $EXTRACT_SPLIT_LINES) {
      # over line limit. Cut off at next source phrase change
			my $sourcePhrase = GetSourcePhrase($line);

			if ($prevSourcePhrase eq "") {
        # start comparing
				$prevSourcePhrase = $sourcePhrase;
			}
			elsif ($sourcePhrase eq $prevSourcePhrase) {
        # can't cut off yet. Do nothing
			}
			else {
        # cut off, open next min-extract file & write to that instead
				close OUT;

        $prevSourcePhrase = "";
				$lineCount = 0;
				++$fileCount;
				my $filePath  = $fileCount;
				$filePath     = "$TMPDIR/extract.$filePath.gz";
				open (OUT, "| gzip -c > $filePath") or die "error starting gzip $!";
			}
		}
    # keep on writing to current mini-extract file
		print OUT "$line\n";
	}
	close OUT;
  ++$fileCount;
}

# create run scripts
my @runFiles = (0..($numParallel-1));
for (my $i = 0; $i < $numParallel; ++$i) {
  my $path = "$TMPDIR/run.$i.sh";
  open(my $fh, ">", $path) or die "cannot open $path: $!";
  $runFiles[$i] = $fh;
}

# write scoring of mini-extracts to run scripts
for (my $i = 0; $i < $fileCount; ++$i) {
  my $numStr = NumStr($i);

  my $fileInd = $i % $numParallel;
  my $fh = $runFiles[$fileInd];
  my $cmd = "$scoreCmd $TMPDIR/extract.$i.gz $lexFile $TMPDIR/mbot-table.half.$numStr.gz $otherExtractArgs 2>> /dev/stderr \n";
  print STDERR $cmd;

  print $fh $cmd;
}

# close run script files
for (my $i = 0; $i < $numParallel; ++$i) {
  close($runFiles[$i]);
  my $path = "$TMPDIR/run.$i.sh";
  systemCheck("chmod +x $path");
}

# run each score script in parallel
my @children;
for (my $i = 0; $i < $numParallel; ++$i) {
  my $cmd = "$TMPDIR/run.$i.sh";
	my $pid = RunFork($cmd);
	push(@children, $pid);
}

# wait for everything is finished
foreach (@children) {
	waitpid($_, 0);
}

# merge & sort
$cmd = "\n\nOH SHIT. This should have been filled in \n\n";
if ($fileCount == 1 && !$doSort) {
  my $numStr = NumStr(0);
  $cmd = "mv $TMPDIR/mbot-table.half.$numStr.gz $ptHalf";
} else {
  $cmd = "gunzip -c $TMPDIR/mbot-table.half.*.gz 2>> /dev/stderr";

  if ($doSort) {
    $cmd .= "| LC_ALL=C $sortCmd -T $TMPDIR ";
  }

  $cmd .= " | gzip -c > $ptHalf  2>> /dev/stderr ";
}
print STDERR $cmd;
systemCheck($cmd);

# merge coc
my $numStr = NumStr(0);
my $cocPath = "$TMPDIR/mbot-table.half.$numStr.gz.coc";

if (-e $cocPath) {
  my @arrayCOC;
  my $line;

  # 1st file
  open(FHCOC, $cocPath) || die "can't open pipe to $cocPath";
  while ($line = <FHCOC>) {
    my $coc = int($line);
    push(@arrayCOC, $coc);
  }
  close(FHCOC);

  # all other files
  for (my $i = 1; $i < $fileCount; ++$i) {
  	$numStr = NumStr($i);

    $cocPath = "$TMPDIR/mbot-table.half.$numStr.gz.coc";
    open(FHCOC, $cocPath) || die "can't open pipe to $cocPath";

    my $arrayInd = 0;
    while ($line = <FHCOC>) {
      my $coc = int($line);
      $arrayCOC[$arrayInd] += $coc;
      ++$arrayInd;
    }
    close(FHCOC);
  }

  # output
  $cocPath = "$ptHalf.coc";
  open(FHCOC, ">", $cocPath) or die "cannot open $cocPath: $!";
  for (my $i = 0; $i < @arrayCOC; ++$i) {
    print FHCOC $arrayCOC[$i]."\n";
  }
  close(FHCOC);
}

$cmd = "rm -rf $TMPDIR \n";
print STDERR $cmd;
systemCheck($cmd);

print STDERR "Finished ".localtime() ."\n";

# -----------------------------------------
# -----------------------------------------

sub RunFork($) {
  my $cmd = shift;

  my $pid = fork();
  if ($pid == 0) { # child
    print STDERR $cmd;
    systemCheck($cmd);
    exit();
  }
  return $pid;
}

sub systemCheck($) {
  my $cmd = shift;
  my $retVal = system($cmd);
  if ($retVal != 0) {
    exit(1);
  }
}

sub GetSourcePhrase($) {
  my $line = shift;
  $line =~ s/^\[MBOT\]\s\|\|\|\s//;
  my $pos = index($line, "|||");
  my $sourcePhrase = substr($line, 0, $pos);
  return $sourcePhrase;
}

sub NumStr($) {
  my $i = shift;
  my $numStr;
  if ($i < 10) {
    $numStr = "0000$i";
  }
  elsif ($i < 100) {
    $numStr = "000$i";
  }
  elsif ($i < 1000) {
    $numStr = "00$i";
  }
  elsif ($i < 10000) {
    $numStr = "0$i";
  }
  else {
    $numStr = $i;
  }
  return $numStr;
}

sub CutContextFile($$$) {
  my ($lastsourcePhrase, $fileCount, $lastline) = @_;
  my $line;
  my $sourcePhrase;

  my $filePath  = "$TMPDIR/extract.context.$fileCount.gz";
  open (OUT_CONTEXT, "| gzip -c > $filePath") or die "error starting gzip $!";

  if ($lastline ne "") {
    print OUT_CONTEXT "$lastline\n";
  }

  #write all lines in context file until we meet last source phrase in extract file
  while ($line=<IN_CONTEXT>) {
    chomp($line);
    $sourcePhrase = GetSourcePhrase($line);
    print OUT_CONTEXT "$line\n";
    if ($sourcePhrase eq $lastsourcePhrase) {
      last;
    }
  }

  #write all lines in context file that correspond to last source phrase in extract file
  while ($line=<IN_CONTEXT>) {
    chomp($line);
    $sourcePhrase = GetSourcePhrase($line);
    if ($sourcePhrase ne $lastsourcePhrase) {
      last;
    }
    print OUT_CONTEXT "$line\n";
  }

  close(OUT_CONTEXT);

  return $line;
}
