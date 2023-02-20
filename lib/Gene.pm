package Table::Gene;

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
my $local_path = __DIR__ . '/';

has tablename	=> 'Gene';
has id_field	=> 'ezgeneid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub fetch_info_ENSG {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		die "Id field for table is not defined\n" unless defined $id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	my $sql_cmd = "select " . join(", ", @fields) . " from `".$class->tablename."` where ensemblId = '$id'";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		++$counter;
		for (my $i = 0; $i < scalar @fields; $i++) {
			$info{$fields[$i]} = encode('utf8', $$row[$i])
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the ",$class->id_field," $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub fetch_info_Symbol {
	my $class = shift;
	my $id = shift;
	my $dbh = $class->{DB}->{mysql};
	unless (defined($id)) {
		$id = $class->get_id;
		die "Id field for table is not defined\n" unless defined $id;
		}
	my %info;
	my @fields = $class->get_field_dic;
	#my $sql_cmd = "select " . join(", ", @fields) . " from `".$class->tablename."` where geneSymbol = '$id' ORDER BY ezGeneId DESC limit 1";
	my $sql_cmd = "select " . join(", ", @fields) . " from (SELECT Gene.ezGeneId as Id, Gene.*, (SELECT COUNT(*) FROM Transcript where Transcript.ezGeneId = Id) as trCount FROM Gene where geneSymbol = '$id') as T ORDER BY trCount DESC limit 1;";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $counter = 0;
	while (my $row = $sth->fetchrow_arrayref) {
		++$counter;
		for (my $i = 0; $i < scalar @fields; $i++) {
			$info{$fields[$i]} = encode('utf8', $$row[$i])
			}
		}
	unless ($counter eq 1) {
		print STDERR "Return $counter rows from database specified with the ",$class->id_field," $id\n" if $verbose;
		return 1;
		}
	$class->{info} = \%info;
	}

sub fetch {
	my $class = shift;
	my $DB = shift;
	my $id = shift;

	my $self = $class->new;
	$self->connect($DB);
	$self->fetch_info($id);
	unless (defined($self->get_id)) {
		$self->fetch_info_ENSG($id);
		}
	unless (defined($self->get_id)) {
		$self->fetch_info_Symbol($id);
		}
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
	}

sub geneDescription_biology_raw {
	my $class = shift;
	my $name = $class->info->{'genesymbol'};
	my $response = Atlas::wrap_python("python $local_path/../../scripts/python/SS_gene_biology_parse.py $name"); # Копируется sheet из шаблона
	$response = [split/\n/, $response];
	my $i = 0;
	my @data;
	while (defined($response->[$i])) {
		if ($response->[$i] eq '!DISEASE') {
			++$i;
			my $code = lc($response->[$i]);
			++$i;
			++$i;
			my $description = '';
			while (1) {
				last if $response->[$i] eq '!LINKS';
				$description = $description.$response->[$i];
				++$i;
				}
			my @links;
			++$i;
			while (1) {
				last if $response->[$i] eq '!END';
				push @links, $response->[$i];
				++$i;
				}
			push @data, {
				"code" => $code,
				"desc" => $description,
				"links" => [@links],
				} if defined $class->{DB}->Pathology($code);
			}
		++$i;
		}
	return \@data;
	}

sub geneDescription_biology_select {
	my $class = shift;
	my $target = shift; #Disease code
	my $data = $class->geneDescription_biology_raw;
	return (((sort {
		$class->{DB}->Pathology($target)->find_distance_up($a->{code}) 
		<=> 
		$class->{DB}->Pathology($target)->find_distance_up($b->{code})} 
		grep {$class->{DB}->Pathology($target)->find_distance_up($_->{code}) > -1} 
		@{$class->geneDescription_biology_raw})[0]) 
		|| undef);
	}

sub geneDescription_biology_links {
	my $class = shift;
	my $name = $class->info->{'genesymbol'};
	my $response = Atlas::wrap_python("python $local_path/../../scripts/python/SS_gene_biology_parse.py $name"); # Копируется sheet из шаблона
	$response = [split/\n/, $response];
	$response = [@{$response}[1..(scalar(@{$response})-1)]];
	my @result;
	foreach my $arg (@{$response}) {
		push (@result, $arg);
		}
	return \@result;
	}






























1;
