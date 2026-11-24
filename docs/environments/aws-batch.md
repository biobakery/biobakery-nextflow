# AWS Batch

The `amazon` profile is an **incomplete porting configuration**, not a prepared
equivalent of the HPC walkthrough. Its presence in the profile list does not
mean every workflow can run with the supplied defaults.

Before using it, configure the AWS region and credentials, Batch queues,
container images, worker AWS CLI path, and S3-accessible inputs/references.
The work directory must use the storage expected by that deployment, such as
`-w s3://BUCKET/work`.

Start by reviewing `conf/profiles/amazon.config` and
`conf/example_yamls/amazon.yaml`. The current profile has legacy profiling
images, including MetaPhlAn 3.1; reconcile their CLI/reference settings before
submitting an analysis. Several helpers and the viral, assembly, and reporting
stages still need image or queue assignments.

Use the [configuration model](../get-started/index.md) to keep the cloud runtime
settings separate from each study's YAML. Follow the
[AWS Batch executor documentation](https://www.nextflow.io/docs/latest/executor.html#aws-batch)
when completing the infrastructure setup. The first successful test should
demonstrate the stages actually configured for your deployment before adding
the rest of the workflow.
