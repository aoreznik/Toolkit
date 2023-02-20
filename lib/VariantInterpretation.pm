package Table::VariantInterpretation;

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

has tablename	=> 'VariantInterpretation';
has id_field	=> 'variantinterpretationid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

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
		} elsif ($id =~ /^(\d+):(\d+)$/) {
		my $molecularTarget_id = $1;
		my $phenotype_id = $2;
		my $sql_cmd = "select variantinterpretationid from `VariantInterpretation` where molecularTargetId = '$molecularTarget_id' and phenotypeId = '$phenotype_id';";
		my $sth = $DB->execute($sql_cmd);
		my $row = $sth->fetchrow_arrayref;
		return undef unless defined $$row[0];
		return $class->fetch($DB, $$row[0]);
		}
	return undef;
	}

sub Phenotype {
	my $class = shift;
	
	my $Phenotype = Table::Phenotype->fetch($class->{DB}, $class->info->{phenotypeid});
	return $Phenotype;
	}

sub history {
	my $class = shift;

	my @result;
	my $sql_cmd = "SELECT variantInterpretationHistoryId from VariantInterpretationHistory where variantInterpretationId = '".$class->get_id."';";
	my $sth = $class->{DB}->execute($sql_cmd);
	while (my $row = $sth->fetchrow_arrayref) {
		push @result, Table::VariantInterpretationHistory->fetch($class->{DB}, $$row[0]);
		}
	return @result;
	}

sub format_text {
	my $class = shift;
	
	my $text;
	my $MT = Table::MolecularTarget->fetch($class->{DB}, $class->info->{moleculartargetid});
	my $Phenotype = Table::Phenotype->fetch($class->{DB}, $class->info->{phenotypeid});
	my $Gene = $class->{DB}->Gene($MT->generateBiomarkerCode);
	my $GPS = Table::GenePhenotypeSignificance->fetch($class->{DB}, $Gene->get_id, $Phenotype->get_id);
	#print STDERR Dumper $GPS->expectedPathologies;exit;
	my @omims = $Phenotype->omims;
	$text = "Наследственные варианты гена ";
	$text = "$text".$Gene->info->{genesymbol};
	$text = "$text ассоциированы с развитием ".decode('UTF-8', $Phenotype->info->{phenotypename_r_genitivecase});
	
	if (lc($GPS->info->{inheritancetype}) eq 'ad') {
		$text = "$text (аутосомно-доминантный тип наследования)";
		} elsif (lc($GPS->info->{inheritancetype}) eq 'ar') {
		$text = "$text (аутосомно-рецессивный тип наследования)";
		}
	if (scalar @omims > 0) {
		map {$_ = $_->get_id} @omims;
		map {$_ = "OMIM#$_"} @omims;
		$text = "$text [".join(';',@omims)."]";
		}
	$text = "$text и могут приводить к развитию следующих онкологических заболеваний: ";
	$text = $text.join(', ', map {decode('UTF-8', $_->info->{pathologyname_r})} $GPS->expectedPathologies).". ";
	$text = $text.decode('UTF-8', $class->info->{interpretationtext_r}) if defined($class->info->{interpretationtext_r});
	$text =~ s/\.$//;
	if (lc($class->info->{interpretationresult}) eq 'pathogenic') {
		$text = "$text. В соответствии с совокупностью приведенных свидетельств в пользу патогенности, вариант классифицирован как патогенный в отношении указанного выше наследственного заболевания (и соответствующего типа наследования).";
		}
	if (lc($class->info->{interpretationresult}) eq 'likely pathogenic') {
		$text = "$text. В соответствии с совокупностью приведенных свидетельств в пользу патогенности, вариант классифицирован как вероятно патогенный в отношении указанного выше наследственного заболевания (и соответствующего типа наследования).";
		}
	if (lc($class->info->{interpretationresult}) eq 'vus') {
		$text = "$text. В соответствии с недостатком свидетельств в пользу патогенности/доброкачественности варианта, вариант классифицирован как вариант неопределенного значения в отношении указанного выше наследственного заболевания (и соответствующего типа наследования)."
		}
	return encode('UTF-8', $text);
	}


























1;
