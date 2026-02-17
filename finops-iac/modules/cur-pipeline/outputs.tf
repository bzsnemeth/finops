output "cur_bucket_arn" {
  description = "ARN of the S3 bucket storing CUR data"
  value       = aws_s3_bucket.cur.arn
}

output "cur_bucket_name" {
  description = "Name of the S3 bucket storing CUR data"
  value       = aws_s3_bucket.cur.id
}

output "athena_database_name" {
  description = "Name of the Glue/Athena database"
  value       = aws_glue_catalog_database.cur.name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup"
  value       = aws_athena_workgroup.finops.name
}

output "glue_crawler_name" {
  description = "Name of the Glue Crawler"
  value       = aws_glue_crawler.cur.name
}
