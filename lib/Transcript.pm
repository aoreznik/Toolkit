package Table::Transcript;

use strict;
use warnings;
use Dir::Self;
use parent 'Table';
use lib __DIR__;

use Aoddb;
use Atlas;
use File::Basename;
use Data::Dumper;
use Storable 'dclone';
use Encode qw(is_utf8 encode decode decode_utf8);
use List::Util qw(max);
use Mojo::Base -base;

has tablename	=> 'Transcript';
has id_field	=> 'transcriptname';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub Gene {
	my $class = shift;
	my $result;
	my $id = $class->info->{ezgeneid};
	return undef unless defined $id;
	$result = Table::Gene->fetch($class->{DB}, $id);
	return $result;
	}

































1;
