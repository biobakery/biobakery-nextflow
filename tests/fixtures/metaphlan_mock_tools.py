#!/usr/bin/env python3
import sys, json, re
from pathlib import Path
args=sys.argv[1:]; tool=Path(sys.argv[0]).name
def opt(*keys):
 for key in keys:
  if key in args: return args[args.index(key)+1]
def write(p,text='test\n'):
 Path(p).parent.mkdir(parents=True,exist_ok=True);Path(p).write_text(text)
if tool=='metaphlan':
 idx=opt('--index');write(opt('-o'),idx+'\n');write(opt('--mapout','--bowtie2out'));write(opt('--samout'))
elif tool=='merge_metaphlan_tables.py':
 values=[Path(p).read_text().strip() for p in args]
 assert len(set(values))==1,values
 print('\n'.join(values))
elif tool=='humann':
 sample=opt('--output-basename')
 for suffix in ['genefamilies','pathabundance','pathcoverage']:write(sample+'_'+suffix+'.tsv',Path(opt('--taxonomic-profile')).read_text())
 write(sample+'_humann_humann_v37.log')
elif tool=='humann_join_tables':
 fs=list(Path(opt('--input')).glob('*'));write(opt('--output'),''.join(p.read_text() for p in fs))
elif tool in ['humann_regroup_table','humann_renorm_table','humann_rename_table']:
 write(opt('-o','--output'),Path(opt('-i','--input')).read_text())
elif tool in ['count_features.py','get_counts_from_humann_logs.py','create_feature_table.py','trim_taxonomy.py']:write(opt('--output'))
elif tool=='baqlava':write(opt('-o')+'/result.tsv')
elif tool=='sample2markers.py':
 name=Path(opt('-i')).name
 # Existing module expects sample.pkl, while SAM includes the index.
 write(name.split('_')[0]+'.pkl')
elif tool=='strainphlan.py':write('output/tree.tre')
elif tool=='python':
 script=Path(args.pop(0)).name
 if script=='biobakery_bootstrap.py':print(opt('--rscript'))
 elif script=='biobakery_identify_inputs.py':
  write(opt('--output'),json.dumps(dict(study_type='WGX',taxonomic_profile='metaphlan/merged/metaphlan_taxonomic_profiles.tsv',ecsabundance='humann/merged/ecs_relab.tsv' if Path('input_folder/humann/merged/ecs_relab.tsv').exists() else None,pathabundance='humann/merged/pathabundance_relab.tsv' if Path('input_folder/humann/merged/pathabundance_relab.tsv').exists() else None,samples_as_columns=True)))
 elif script=='stats_covariate_equation.py':write(opt('--output'),json.dumps(dict(run_multivariate=True,run_pairwise=True,covariate_equation='age')))
 elif script in ['biobakery_vis_report.py','biobakery_stats_report.py']:
  folder=opt('--output'); taxonomy=Path('input_folder/metaphlan/merged/metaphlan_taxonomic_profiles.tsv') if folder=='vis' else Path(opt('--taxonomic-profile'))
  identity=taxonomy.read_text()
  write(folder+'/'+folder+'_report.html',identity);write(folder+'/'+folder+'_report.pdf',identity)
 elif script=='stats_stratified_metadata.py':
  write(opt('--output'));write(opt('--plan'),json.dumps(dict(metadata_end=2,plots=[dict(number=1,variable='age')])))
 elif script=='maaslin_image_tiles.py':pass
 elif script=='rna_dna_norm_py3.py':
  identity=Path(opt('--input-dna')).read_text(); assert set(identity.split())==set(Path(opt('--input-rna')).read_text().split())
  for suffix in ['unstratified','no_unclassifed']:write(opt('--output')+'/rna_dna_relative_expression_'+suffix+'.tsv')
  write(opt('--output')+'/rna_dna_relative_expression.tsv',identity)
 else:write(opt('--output'))
elif tool=='Rscript':
 script=args[0]
 if script=='alpha_diversity':write(args[3]+'/plot.png')
 elif script in ['beta_diversity','mantel_test']:write(args[3])
 elif script=='permanova_hmp2':write(args[3])
 else:raise RuntimeError(args)
elif tool=='R':
 match=re.search(r"'((?:maaslin2_)[^']+)'",args[1]);write(match[1]+'/significant_results.tsv')
elif tool=='halla':write(opt('-o')+'/all_associations.txt')
else:raise RuntimeError(tool)
