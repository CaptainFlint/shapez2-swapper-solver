#!/usr/bin/perl

use strict;
use warnings;

my $DEBUG = 0;  # Debug mode

=begin comment

Usage:
$ perl solver.pl LANES_IN LANES_OUT [MAX_SWAPS] [F]
LANES_IN - comma-separated list of input shapes, e.g. aaaa,bbcd
LANES_OUT - comma-separated list of desired output
MAX_SWAPS - maximum amount of swappers (default: 6)
F - use flat mode (only neighboring lanes are swapped)


Notations

1. Shapes
Shapes are encoded as a sequence of arbitrary symbols, each symbol representing a piece (corner).
The length of the string must be equal to the $MODE value.

There is no mapping between the symbols used here and the actual shapes from the game, only the rule
that identical symbols mean identical pieces, and different ones mean different pieces.
All layers are considered one piece; crystal breaking or gravity are NOT supported.

Examples:
'aaaaaa' - some hex mode shape where all pieces are identical, e.g. HuHuHuHuHuHu, or FgFgFgFgFgFg.
'abcc' - a square mode shape that might look like CuRuSuSu, or CwWgRyRy.

2. RSwaps
RSwap (rotate-swap) sequences are encoded in the format of: 'nXmY' where:
* n, m are the amount of rotations applied to each input;
* X, Y are the identifiers of lanes being swapped.

Example:
'0132' - put 3 rotators in lane no.2, then a swapper between lanes no.1 and no.2.
'2013' - put 2 rotators in lane no.0, a single rotator in lane no.3; and swap lanes no.0 and 3.

3. Rotates
The final rotation-only step can be present. Its format is: 'rXYZ...' where:
* r is a fixed letter "r";
* X, Y, Z, etc. are the amounts of rotations for each lane (all lanes, the amount is equal to $MODE).

=end comment

=cut

if (scalar(@ARGV) < 2) {
	print "Usage: solver.pl LANES_IN LANES_OUT [MAX_SWAPS] [F]\n";
	exit 1;
}
# Shapes on the input lanes
my @inputLanes  = split(m/,/, $ARGV[0]);
# The desired output
my @outputLanes = split(m/,/, $ARGV[1]);
# Maximum amount of operations in the chain
my $maxChain = 6;
# Whether flat mode is used
my $flatMode = 0;

for my $a (@ARGV[2..3]) {
	if (defined($a)) {
		if (lc($a) eq 'f') {
			$flatMode = 1;
		}
		elsif ($a =~ m/^\d+$/) {
			$maxChain = $a;
		}
	}
}

my $MODE = length($inputLanes[0]);

# Consistency checks
if (($MODE != 4) && ($MODE != 6)) {
	die "Unsupported shape size (${MODE}); can only be 4 or 6.";
}
if (scalar(@inputLanes) != scalar(@outputLanes)) {
	die "There should be the same amount of input and output lanes!";
}
for (my $i = 0; $i < scalar(@inputLanes); ++$i) {
	if (length($inputLanes[$i]) != $MODE) {
		die "Input shape No.${i} has invalid length!";
	}
	if (length($outputLanes[$i]) != $MODE) {
		die "Output shape No.${i} has invalid length!";
	}
}
if (join('', sort(split(m//, join('', @inputLanes)))) ne join('', sort(split(m//, join('', @outputLanes))))) {
	die "Non-equal amount of pieces between inputs and outputs!";
}


# Apply the specified amount of rotation steps to the shape
# Arguments: shape, amount of rotations
sub rotateShape($$) {
	my ($shape, $steps) = @_;
	return substr($shape, -$steps) . substr($shape, 0, -$steps);
}

# Apply a rotate-swap operation
# Lanes are defined as an array, each element is a shape sent via this lane.
sub applyRSwap($$) {
	my ($lanes, $op) = @_;
	my @lanesNew = @$lanes;
	my ($r1, $l1, $r2, $l2) = split(m//, $op);
	$lanesNew[$l1] = rotateShape($lanesNew[$l1], $r1);
	$lanesNew[$l2] = rotateShape($lanesNew[$l2], $r2);
	my $s1 = substr($lanesNew[$l1], 0, $MODE / 2) . substr($lanesNew[$l2], $MODE / 2, $MODE / 2);
	my $s2 = substr($lanesNew[$l2], 0, $MODE / 2) . substr($lanesNew[$l1], $MODE / 2, $MODE / 2);
	$lanesNew[$l1] = $s1;
	$lanesNew[$l2] = $s2;
	print '  ' . join(',', @$lanes) . " : ${op} => " . join(',', @lanesNew) . $/ if ($DEBUG);
	return \@lanesNew;
}
# Apply a rotate-only operation
sub applyRotation($$) {
	my ($lanes, $op) = @_;
	my @lanesNew = ();
	for (my $l = 0; $l < scalar(@$lanes); ++$l) {
		$lanesNew[$l] = rotateShape($lanes->[$l], substr($op, $l + 1, 1));
	}
	print '  ' . join(',', @$lanes) . " : ${op} => " . join(',', @lanesNew) . $/ if ($DEBUG);
	return \@lanesNew;
}

# Apply a sequence of operations.
sub apply($$) {
	my ($lanes, $seq) = @_;
	my @lanesNew = @$lanes;
	for my $op (@$seq) {
		if (substr($op, 0, 1) eq 'r') {
			@lanesNew = @{applyRotation(\@lanesNew, $op)};
		}
		else {
			@lanesNew = @{applyRSwap(\@lanesNew, $op)};
		}
	}
	return \@lanesNew;
}

# Compare two arrays of strings
sub arraysEqual($$) {
	my ($a, $b) = @_;
	return 0 if (scalar(@$a) != scalar(@$b));
	for (my $i = 0; $i < scalar(@$a); ++$i) {
		return 0 if ($a->[$i] ne $b->[$i]);
	}
	return 1;
}


# The solver enumerates all permutations of possible swappers and tries to find those that give
# the desired output configuration.
# Starting with one swapper (trying all combinations of rotators, and all pairs of lanes),
# then increasing the chain length.

# Counter for total amount of configurations
my $cfgCounter = 0;
# Amount of found solutions
my $solutionsFound = 0;

# Recursively generate and process all possible permutations.
# Arguments:
#   $lanes    - the state of lanes achieved at the current step
#   $seq      - the sequence of operations that led to the current state
#   $maxSteps - maximum amount of steps left to do
sub generatePermutations($$$);
sub generatePermutations($$$) {
	my ($lanes, $seq, $maxSteps) = @_;
	my $dbgHdr = 'generatePermutations([' . join(',', @$lanes) . '], [' . join(',', @$seq) . '], ' . $maxSteps . ')';
	print "${dbgHdr}\n" if ($DEBUG);
	if ($maxSteps == 0) {
		++$cfgCounter;
		# Check if adding extra rotations will give us the desired result
		my $failed = 0;
		my $rotationStep = 'r';
		for (my $l = 0; $l < scalar(@inputLanes); ++$l) {
			my $laneSuccessful = 0;
			for (my $r = 0; $r < $MODE; ++$r) {
				if (rotateShape($lanes->[$l], $r) eq $outputLanes[$l]) {
					$rotationStep .= $r;
					$laneSuccessful = 1;
					last;
				}
			}
			if (!$laneSuccessful) {
				$failed = 1;
				last;
			}
		}
		if (!$failed) {
			++$solutionsFound;
			print '  ' . join(',', @$seq) . ",${rotationStep}\n";
			# Internal consistency checks
			my @lanesNew1 = @{applyRotation($lanes, $rotationStep)};
			my @lanesNew2 = @{apply(\@inputLanes, [@$seq, $rotationStep])};
			if (!arraysEqual(\@outputLanes, \@lanesNew1) || !arraysEqual(\@outputLanes, \@lanesNew2)) {
				print "  ERROR! Inconsistent results!\n";
				print "  Desired output:  " . join(',', @outputLanes) . "\n";
				print "  Achieved output: " . join(',', @lanesNew1) . "\n";
				print "  Rebuilt output:  " . join(',', @lanesNew2) . "\n\n";
			}
		}
		print "exit:${dbgHdr}\n" if ($DEBUG);
		return;
	}
	# Enumerate possible swapper positions
	for (my $l1 = 0; $l1 < scalar(@inputLanes) - 1; ++$l1) {
		my @secondLanes = ();
		if ($flatMode) {
			@secondLanes = ($l1 + 1);
		}
		else {
			@secondLanes = ($l1 + 1 .. $#inputLanes);
		}
		for my $l2 (@secondLanes) {
			# Exclude rotations with identical results
			my %rotations1 = ();
			my %rotations2 = ();
			for (my $r = 0; $r < $MODE; ++$r) {
				my $s = rotateShape($lanes->[$l1], $r);
				if (!defined($rotations1{$s})) {
					$rotations1{$s} = $r;
				}
				$s = rotateShape($lanes->[$l2], $r);
				if (!defined($rotations2{$s})) {
					$rotations2{$s} = $r;
				}
			}
			my %rotationSteps1 = reverse(%rotations1);
			my %rotationSteps2 = reverse(%rotations2);
			for my $r1 (sort(keys(%rotationSteps1))) {
				for my $r2 (sort(keys(%rotationSteps2))) {
					my $op = "${r1}${l1}${r2}${l2}";
					generatePermutations(applyRSwap($lanes, $op), [@$seq, $op], $maxSteps - 1);
				}
			}
		}
	}
	print "exit:${dbgHdr}\n" if ($DEBUG);
}

sub formatDateTime(;$) {
	my $tm = (defined($_[0]) ? $_[0] : time());
	my ($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime($tm);
	return sprintf("%02d.%02d.%04d %02d:%02d:%02d", $mday, ($mon + 1), ($year + 1900), $hour, $min, $sec);
}

sub formatTimeDelta($) {
	my ($dt) = @_;
	return '0s' if (!$dt);
	my @dt_parts = ();
	my @dt_part_names = ('d', 'h', 'm', 's');
	for my $u (60, 60, 24) {
		unshift(@dt_parts, int($dt % $u));
		$dt = int($dt / $u);
	}
	unshift(@dt_parts, $dt);
	my $timeFmt = '';
	for my $i (0 .. $#dt_parts) {
		if (!$timeFmt) {
			next if ($dt_parts[$i] == 0);
			$timeFmt = $dt_parts[$i] . $dt_part_names[$i];
		}
		else {
			$timeFmt .= sprintf(':%02d', $dt_parts[$i]);
		}
	}
	return $timeFmt;
}

# Start looking for the solution, increasing the amount of swappers
for (my $swappers = 1; $swappers <= $maxChain; ++$swappers) {
	print "Trying the amount of operations: ${swappers}...\n";
	$cfgCounter = 0;
	my $t1 = time();
	generatePermutations(\@inputLanes, [], $swappers);
	my $t2 = time();
	my $dtTxt = formatTimeDelta($t2 - $t1);
	my $cfgCounterTxt = reverse((reverse($cfgCounter) =~ s/(...)/$1./gr) =~ s/\.$//r);
	print "  Time passed: ${dtTxt}\n  Configurations checked: ${cfgCounterTxt}\n";
	if ($solutionsFound) {
		print "  Solutions found: ${solutionsFound}\n";
		last;
	}
}
