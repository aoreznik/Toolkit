package Table::Mutation;

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

has tablename	=> 'Mutation';
has id_field	=> 'mutationid';

our @EXPORT     = qw/ $verbose /;
our $verbose    = 0;

sub name {
	my $class = shift;
	
	if ($class->info->{eventtypegeneral} eq 'SNP') {
		return undef unless defined $class->info->{mutationchr};
		return undef unless defined $class->info->{mutationgenomicpos};
		return undef unless defined $class->info->{mutationref};
		return undef unless defined $class->info->{mutationalt};
		my $name = $class->info->{mutationchr} . ":" . 
			$class->info->{mutationgenomicpos} . 
			$class->info->{mutationref} . ">" .
			$class->info->{mutationalt};
		return lc($name);
		}
	return undef;
	}

sub connect_analysis {
	my $class = shift;
	my $analysis_name = shift;
	
	my $analysis = $class->{DB}->Analysis($analysis_name);
	return 1 unless defined $analysis;
	
	my $sql_cmd = "SELECT * FROM MutationResult WHERE analysisName = '".$analysis_name."' AND mutationId = '".$class->get_id."';";
	my $sth = $class->{DB}->execute($sql_cmd);
	return 1 unless defined $sth;
	while (my $row = $sth->fetchrow_hashref("NAME_lc")) {
		foreach my $field (keys %{$row}) {
			$class->{info}->{$field} = $row->{$field};
			}
		}
	}

sub DBfreq {
	my $class = shift;
	my $options = shift; # AVIALABLE KEYS: panel (Barcode.panelCode)
	my @control_analyses = $class->{DB}->control_analyses($options);
	if ((scalar @control_analyses) eq 0) {
		return 0;
		}
	my $DBcount = $class->{DB}->execute_select_single("select COUNT(*) FROM MutationResult INNER JOIN Mutation ON Mutation.mutationId = MutationResult.mutationId where CONCAT(Mutation.mutationChr,\":\",Mutation.mutationGenomicPos,Mutation.mutationRef,\">\",Mutation.mutationAlt) = '".$class->name."' and analysisName in (".join(',', map{"'" . $_->get_id . "'"} @control_analyses).");"); # Среди всех контрольных анализов выбираются мутации из таблицы MutationResult. Это делается чтобы оценить частоту конкретной мутации среди контрольных анализов. Выбираются без обращения внимания на поля PASS и QUAL - смотрится частота среди артефактов тоже.
	my $DBfreq = $DBcount / (scalar @control_analyses);
	return $DBfreq;
	}

sub DBcount {
	my $class = shift;
	my $options = shift; # AVIALABLE KEYS: panel (Barcode.panelCode)
	my @control_analyses = $class->{DB}->control_analyses($options);
	if ((scalar @control_analyses) eq 0) {
		return 0;
		}
	my $DBcount = $class->{DB}->execute_select_single("select COUNT(*) FROM MutationResult INNER JOIN Mutation ON Mutation.mutationId = MutationResult.mutationId where CONCAT(Mutation.mutationChr,\":\",Mutation.mutationGenomicPos,Mutation.mutationRef,\">\",Mutation.mutationAlt) = '".$class->name."' and analysisName in (".join(',', map{"'" . $_->get_id . "'"} @control_analyses).");"); # Среди всех контрольных анализов выбираются мутации из таблицы MutationResult. Это делается чтобы оценить частоту конкретной мутации среди контрольных анализов. Выбираются без обращения внимания на поля PASS и QUAL - смотрится частота среди артефактов тоже.
	return $DBcount;
	}

sub count {
	my $class = shift;
	my $options = shift; # AVIALABLE KEYS: filter (MutationResult.filter), role (Analysis.analysisRole), qc (LibraryQC.result), batch (Analysis.analysisbatch), panel (Barcode.panelCode);
	$options = {} unless defined $options;
	
	my $sql_cmd = "select COUNT(MutationResult.mutationId) FROM MutationResult INNER JOIN Analysis ON Analysis.analysisName = MutationResult.analysisName INNER JOIN Barcode ON Analysis.barcodeName = Barcode.barcodeName LEFT JOIN LibraryQC ON LibraryQC.barcodeName = Barcode.barcodeName where MutationResult.mutationId = ". $class->get_id;
	if (defined $options->{filter}) {
		$sql_cmd = "$sql_cmd and MutationResult.filter = '".$options->{filter}."'";
		}
	if (defined $options->{role}) {
		$sql_cmd = "$sql_cmd and Analysis.analysisRole = '".$options->{role}."'";
		}
	if (defined($options->{batch})) {
		$sql_cmd = "$sql_cmd and Analysis.analysisBatch = '".$options->{batch}."'";
		}
	if (defined($options->{qc})) {
		$sql_cmd = "$sql_cmd and LibraryQC.result = '".$options->{qc}."'";
		}
	if (defined($options->{panel})) {
		$sql_cmd = "$sql_cmd and Barcode.panelCode = '".$options->{panel}."'";
		}
	$sql_cmd = "$sql_cmd;";
	my $sth = $class->{DB}->execute($sql_cmd);
	my $row = $sth->fetchrow_arrayref;
	return $$row[0];
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
		} elsif ($id =~ /^(\S+):(\d+)([AGCTNagctn]+)>([AGCTNagctn]+)$/) {
		my $chr = lc($1);
		my $pos = lc($2);
		my $ref = lc($3);
		my $alt = lc($4);
		my $sql_cmd = "select mutationId from Mutation where mutationChr = '$chr' and mutationGenomicPos = '$pos' and mutationRef = '$ref' and mutationAlt = '$alt' and eventTypeGeneral = 'SNP';";
		my $sth = $DB->execute($sql_cmd);
		my $row = $sth->fetchrow_arrayref;
		return undef unless defined $$row[0];
		return $DB->Mutation($$row[0]);
		} else {
		}
	return undef;
	}

sub VariantAnnotation {
	my $class = shift;
	my $transcript = shift;
	my $Annotation;
	if (defined($transcript)) {
		$Annotation = Table::VariantAnnotation->fetch($class->{DB}, $class->get_id, $transcript);
		return $Annotation;
		} else {
		my $command = "SELECT annotationid FROM PrimaryAnnotation where mutationid = ".$class->get_id;
		my $annotation_id = $class->{DB}->execute_select_single($command);
		return undef unless defined $annotation_id;
		$Annotation = Table::VariantAnnotation->fetch($class->{DB}, $annotation_id);
		}
	}

sub HGVS_name {
	my $class = shift;
	my $VariantAnnotation = $class->VariantAnnotation;
	if ((defined($VariantAnnotation->info->{hgvsp}))and(length($VariantAnnotation->info->{hgvsp}) > 1)) {
		return 'p.'.$VariantAnnotation->info->{hgvsp};
		}
	if ((defined($VariantAnnotation->info->{hgvsc}))and(length($VariantAnnotation->info->{hgvsc}) > 1)) {
		return 'c.'.$VariantAnnotation->info->{hgvsc};
		}
	return $class->name;
	}

sub setPrimaryAnnotation {
	my $class = shift;
	my $annotationId = shift;
	my $command = "INSERT INTO `PrimaryAnnotation` (mutationid, annotationid) VALUES ('".$class->get_id."', '".$annotationId."')";
	$class->{DB}->execute($command);
	}

sub PopulationFrequency {
	my $class = shift;
	my $populationCode = shift;
	if (defined ($populationCode)) {
		$populationCode = lc($populationCode);
		my $PopulationFrequency_Test = Table::PopulationFrequency->new;
		$PopulationFrequency_Test->connect($class->{DB});
		my $PopulationProjectDic_Test = Table::PopulationProjectDic->new;
		$PopulationProjectDic_Test->connect($class->{DB});
		my $command = "SELECT `".$PopulationFrequency_Test->id_field."` FROM `PopulationFrequency` where `" . $class->id_field . "` = '" . $class->get_id . "' and `" . $PopulationProjectDic_Test->id_field . "` = '$populationCode';";
		my $population_freq_id = $class->{DB}->execute_select_single("$command");
		return undef unless defined $population_freq_id;
		return Table::PopulationFrequency->fetch($class->{DB}, $population_freq_id);
		} else {
		my @projectDic = $class->{DB}->PopulationProjectDic;
		foreach my $project (sort {$a->info->{priority} <=> $b->info->{priority}} @projectDic) {
			my $PopulationFrequency = $class->PopulationFrequency($project->info->{$project->id_field});
			next unless defined $PopulationFrequency;
			return $PopulationFrequency;
			}
		return undef;
		}
	}

sub createRule { # create record for table MutationRule
	my $class = shift;
	my $zyg = shift;
	
	my $info;
	$info->{mutationid} = $class->get_id;
	$info->{zygosity} = $zyg;
	my $rule_id = Table::MutationRule->insert_row($class->{DB}, $info);
	my $MutationRule = Table::MutationRule->fetch($class->{DB}, $rule_id);
	return $MutationRule;
	}

sub fetchRule { # fetch record from table MutationRule
	my $class = shift;
	my $zyg = shift;
	
	my $name = $class->name . ":$zyg";
	my $MutationRule = Table::MutationRule->fetch($class->{DB}, $name);
	unless (defined($MutationRule)) {
		$MutationRule = $class->createRule($zyg);
		}
	return $MutationRule;
	}

sub isRejectedPFQ {
	my $Mutation = shift;
	return 0 if lc($Mutation->name) eq 'chr19:17945696c>t'; # JAK3 V722I
	my $exac;
	my $topmed;
	my $kg;
	if (defined($Mutation->PopulationFrequency('EXAC'))) {
		$exac = $Mutation->PopulationFrequency('EXAC')->info->{freq};
		return 'high EXAC frequency (threshold 0.3%)' if $exac > 0.003;
		} else {$exac = 0}
	if (defined($Mutation->PopulationFrequency('TOPMED'))) {
		$topmed = $Mutation->PopulationFrequency('TOPMED')->info->{freq};
		return 'high TOPMED frequency (threshold 0.3%)' if $topmed > 0.003;
		} else {$topmed = 0}
	if (defined($Mutation->PopulationFrequency('1000G'))) {
		$kg = $Mutation->PopulationFrequency('1000G')->info->{freq};
		if ($kg > 0.003) {
			if (($exac > 0.0003) or ($topmed > 0.0003)) {return 'high 1000G frequency (threshold 0.3%)'} # Из-за возможности ошибки в 1000G
			}
		}
	if ((($exac > 0.001)or($topmed > 0.001))and
		(($exac > 0.000333) and ($topmed > 0.000333))) {
		return 'high EXAC/TOPMED frequency (threshold 0.1%)';
		}
	return 0;
	}

sub isRejectedVCS {
	my $Mutation = shift;
	my $VariantAnnotation = $Mutation->VariantAnnotation;
	return 'UnAnnotated' unless defined $VariantAnnotation;
	my %desiredConsequence;
	foreach my $cons (qw(coding_sequence_variant feature_elongation feature_truncation frameshift_variant incomplete_terminal_codon_variant inframe_deletion inframe_insertion mature_miRNA_variant missense_variant protein_altering_variant regulatory_region_ablation regulatory_region_amplification regulatory_region_variant splice_acceptor_variant splice_donor_variant splice_region_variant start_lost start_retained_variant stop_gained stop_lost stop_retained_variant TFBS_ablation TFBS_amplification TF_binding_site_variant transcript_ablation transcript_amplification)) {
		$desiredConsequence{lc($cons)} = 1;
		}
	my $isDesired = 0;
	foreach my $VariantConsequence ($VariantAnnotation->consequences) {
		my $cons = lc($VariantConsequence->info->{variantconsequence});
		if (defined($desiredConsequence{$cons})) {
			$isDesired = 1;
			last;
			}
		}
	return 'unwanted consequence' if $isDesired eq 0;
	return 0;
	}

sub clinicalInterpretation_GC {
	# Automatic clinical interpretation for medical genetics 
	# (Filling table VariantInterpetation)
	my $Mutation = shift;

	my %geneDic;
	map {$geneDic{$_} = 1} qw(BRCA1 BRCA2);

	my $mutationRule_name = $Mutation->name.":germline_het";
	my $MT = Table::MutationRule->forceFetch($Mutation->{DB}, $mutationRule_name);
	my $VA = $Mutation->VariantAnnotation;
	if (defined($geneDic{$VA->Transcript->Gene->info->{genesymbol}})) {
		$Mutation->clinicalInterpretation_truncating_CLINVAR;
		}
	}

sub clinicalInterpretation_truncating_CLINVAR {
	# Найти все патогенные варианты этого гена (фреймшифт или нонсенс)
	# Посмотреть как позиция конкретного варианта соотносится с позицией самого дальнего патогенного транкирующего варианта
	my $Mutation = shift;
	
	open (CLINVAR, "<".$Mutation->{DB}->config->{"data_path"}->{"CLINVAR"});

	my @pathogenic_pos; # массив позиций патогенных вариантов
	my $Gene = $Mutation->VariantAnnotation->Transcript->Gene;
	my $geneString = $Gene->info->{genesymbol}.":".$Gene->info->{ezgeneid};
	while (<CLINVAR>) {
		next if m!#!;
		my $line = $_;
		my @mas = split/\t/;
		my @info = split/;/, $mas[7];
		next unless defined Atlas::VCFinfo($line, "GENEINFO");
		next unless defined Atlas::VCFinfo($line, "CLNSIG");
		next unless defined Atlas::VCFinfo($line, "MC");
		next unless Atlas::VCFinfo($line, "GENEINFO") eq $geneString;
		next unless Atlas::VCFinfo($line, "CLNSIG") =~ /Pathogenic/;
		next unless ((Atlas::VCFinfo($line, "MC") =~ /nonsense/) or (Atlas::VCFinfo($line, "MC") =~ /frameshift_variant/));
		print STDERR "!$line\n";
		#push (@pathogenic_pos)
		}

	close CLINVAR;
	}



























1;
