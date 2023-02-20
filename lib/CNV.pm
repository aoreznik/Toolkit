package Table::CNV;

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

has tablename	=> 'CNV';
has id_field	=> 'cnvid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub name {
	my $class = shift;
	my $Gene = $class->{DB}->Gene($class->info->{ezgeneid});
	return "".lc($Gene->info->{genesymbol}).":".lc($class->info->{type});
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;
	
	my $self = $class->new;
	$self->connect($DB);
	if ($id =~ /^(\d+)$/) {
		$self->fetch_info($id);
		eval {$self->get_id};
		if ($@) {
			print STDERR "$@" if $verbose;
			return undef;
			} else {
			if (defined $self->get_id) {
				return $self;
				} else {
				print STDERR "Could not fetch data from table",$class->tablename,"\n" if $verbose;
				return undef;
				}
			}
		} elsif ($id =~ /^(\S+):(\S+)$/) {
		my $symbol = lc($1);
		my $type = lc($2);
		my $Gene = $DB->Gene($symbol);
		#print STDERR "GENE : $symbol";
		my $sql_cmd = "select CNVId from CNV where ezGeneId = '".$Gene->info->{ezgeneid}."' and type = '$type';";
		my $sth = $DB->execute($sql_cmd);
		my $row = $sth->fetchrow_arrayref;
		return undef unless defined $$row[0];
		return $DB->CNV($$row[0]);
		}
	return undef;
	}
		
sub Gene {
	my $class = shift;
	return $class->{DB}->Gene($class->info->{ezgeneid});
	}

#sub fetchRule { # fetch record from table CNVRule (or force create)
#	my $class = shift;
#	my $status = shift;
	
#	my $name = $class->name . ":$status";#
#	my $CNVRule = Table::CNVRule->fetch($class->{DB}, $name);
#	unless (defined($CNVRule)) {
#		$CNVRule = $class->createRule($status);
#		}
#	return $CNVRule;
#	}

#sub createRule { # create record for table CNVRule
#	my $class = shift;
#	my $status = shift;
	
#	my $info;
#	$info->{cnvid} = $class->get_id;
#	$info->{status} = $status;
#	my $rule_id = Table::CNVRule->insert_row($class->{DB}, $info);
#	my $CNVRule = Table::CNVRule->fetch($class->{DB}, $rule_id);
#	return $CNVRule;
#	}





















1;
