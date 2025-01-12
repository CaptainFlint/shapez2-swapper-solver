#!/usr/bin/perl

use strict;
use warnings;

my $MODE = 6; # Amount of pieces in a shape

=begin comment

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

2. Swaps
Swap sequences are encoded in the format of: 'AnXmY' where:
* A is either '+' (apply the swapper) or '-' (only rotators), '-' can only be the last in chain;
* n, m are the amount of rotations applied to each input;
* X, Y are the identifiers of lanes being swapped.

Example:
'+0132' - put 3 rotators to shapes in lane no.2, then a swapper between lanes no.1 and no.2.
'-2013' - put 2 rotators to shapes in lane no.0, and a single rotator in lane no.3; no swapper.

=end comment

=cut

# Apply the specified amount of rotation steps to the shape
# Arguments: shape, amount of rotations
sub applyRotation($$) {
	my ($shape, $steps) = @_;
	$shape = substr($shape, -$steps) . substr($shape, 0, -$steps);
	return $shape;
}

# Apply a sequence of buildings to input shapes.
# Lanes are defined as an array, each element is a shape sent via this lane.
# Sequence is an array of swap instructions.
sub apply($$) {
	my ($lanes, $seq) = @_;
	my @lanesNew = @$lanes;
	for (my $i = 0; $i < scalar(@$seq); ++$i) {
		my ($a, $r1, $l1, $r2, $l2) = split(m//, $seq->[$i]);
		$lanesNew[$l1] = applyRotation($lanesNew[$l1], $r1);
		$lanesNew[$l2] = applyRotation($lanesNew[$l2], $r2);
		if ($a eq '+') {
			my $s1 = substr($lanesNew[$l1], 0, $MODE / 2) . substr($lanesNew[$l2], $MODE / 2, $MODE / 2);
			my $s2 = substr($lanesNew[$l2], 0, $MODE / 2) . substr($lanesNew[$l1], $MODE / 2, $MODE / 2);
			$lanesNew[$l1] = $s1;
			$lanesNew[$l2] = $s2;
		}
	}
	#print join(',', @$lanes) . $/ . join(',', @$seq) . $/ . join(',', @lanesNew) . $/ . $/;
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

sub test() {
	my @lanes = ('aaaaaa', 'bbbbbb', 'cccccc');
	apply(\@lanes, ['+0001', '-1001']);
	print join(', ', @lanes) . "\n";
}
#test();
#exit;

# The solver enumerates all permutations of possible swappers and tries to find those that give
# the desired output configuration.
# Starting with one swapper (trying all combinations of rotators, and all pairs of lanes),
# then increasing the chain length.

# Shapes on the input lanes
my @inputLanes  = ('aaaaaa', 'bbbbbb', 'cccccc');
# The desired output
my @outputLanes2 = ('aaaaaa', 'ccbbbc', 'cccbbb');
my @outputLanes = ('abcabc', 'abcabc', 'abcabc');
# Maximum amount of operations in the chain
my $maxChain = 6;

# Consistency checks
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

# Recursively generate and process all possible permutations.
# Arguments:
#   $chain - the current state of the swapper chain
#   $level - current processing level (the identifier of the swapper in the chain)
sub generatePermutations($$);
sub generatePermutations($$) {
	my ($chain, $level) = @_;
	# Calculating state of lanes up to the current level to exclude meaningless rotations
	my @partialChain;
	if ($level == 0) {
		@partialChain = @inputLanes;
	}
	else {
		@partialChain = @{apply(\@inputLanes, [@{$chain}[0 .. $level - 1]])};
	}
	for (my $l1 = 0; $l1 < scalar(@inputLanes) - 1; ++$l1) {
		for (my $l2 = $l1 + 1; $l2 < scalar(@inputLanes); ++$l2) {
			my %rotations1 = ();
			my %rotations2 = ();
			for (my $r = 0; $r < $MODE; ++$r) {
				my $s = applyRotation($partialChain[$l1], $r);
				if (!defined($rotations1{$s})) {
					$rotations1{$s} = $r;
				}
				$s = applyRotation($partialChain[$l2], $r);
				if (!defined($rotations2{$s})) {
					$rotations2{$s} = $r;
				}
			}
			for my $r1 (sort(values(%rotations1))) {
				for my $r2 (sort(values(%rotations2))) {
					my $op = "${r1}${l1}${r2}${l2}";
					if ($level == scalar(@$chain) - 1) {
						for my $a ('+', '-') {
							$chain->[$level] = "${a}${op}";
							my $output = apply(\@inputLanes, $chain);
							if (arraysEqual($output, \@outputLanes)) {
								print "Found solution:\n" . join(',', @$chain) . "\n\n";
							}
						}
					}
					else {
						$chain->[$level] = "+${op}";
						generatePermutations($chain, $level + 1);
					}
				}
			}
		}
	}
}

# Start looking for the solution, increasing the amount of swappers
for (my $swappers = 1; $swappers <= $maxChain; ++$swappers) {
	print "Trying the amount of operations: ${swappers}...\n";
	my @chain = ('+0001') x $swappers;
	generatePermutations(\@chain, 0);
}
