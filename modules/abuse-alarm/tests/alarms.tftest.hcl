# Unit tests for abuse-alarm: spec defaults, name shaping, SNS wiring,
# and the recovery-notification toggle. Mocked AWS provider -- no creds.

# A realistic SNS ARN so the alarm resource's ARN validation on
# alarm_actions / ok_actions passes under the mock.
mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:unit-abuse-alarms"
    }
  }
}

variables {
  name = "unit"
}

run "spec_defaults_are_applied" {
  command = plan

  variables {
    alarms = {
      ddb-write = {
        metric_name = "ConsumedWriteCapacityUnits"
        dimensions  = { TableName = "unit-events" }
        threshold   = 20000
      }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.this["ddb-write"].alarm_name == "unit-ddb-write"
    error_message = "alarm name should be <var.name>-<key>"
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.this["ddb-write"].namespace == "AWS/DynamoDB"
    error_message = "namespace should default to AWS/DynamoDB"
  }
  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["ddb-write"].statistic == "Sum" &&
      aws_cloudwatch_metric_alarm.this["ddb-write"].period == 300 &&
      aws_cloudwatch_metric_alarm.this["ddb-write"].evaluation_periods == 1 &&
      aws_cloudwatch_metric_alarm.this["ddb-write"].comparison_operator == "GreaterThanThreshold" &&
      aws_cloudwatch_metric_alarm.this["ddb-write"].treat_missing_data == "notBreaching"
    )
    error_message = "the sum-over-5-min / first-breach defaults should apply"
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["ddb-write"].ok_actions) == 1
    error_message = "notify_on_recovery defaults true, so ok_actions should be set"
  }
}

run "spec_overrides_pass_through" {
  command = plan

  variables {
    alarms = {
      lambda-flood = {
        namespace           = "AWS/Lambda"
        metric_name         = "Invocations"
        dimensions          = { FunctionName = "unit-voice" }
        period              = 60
        evaluation_periods  = 3
        datapoints_to_alarm = 2
        threshold           = 300
        comparison_operator = "GreaterThanOrEqualToThreshold"
      }
    }
  }

  assert {
    condition = (
      aws_cloudwatch_metric_alarm.this["lambda-flood"].namespace == "AWS/Lambda" &&
      aws_cloudwatch_metric_alarm.this["lambda-flood"].period == 60 &&
      aws_cloudwatch_metric_alarm.this["lambda-flood"].evaluation_periods == 3 &&
      aws_cloudwatch_metric_alarm.this["lambda-flood"].datapoints_to_alarm == 2 &&
      aws_cloudwatch_metric_alarm.this["lambda-flood"].comparison_operator == "GreaterThanOrEqualToThreshold"
    )
    error_message = "explicit spec fields should pass through unchanged"
  }
}

run "recovery_toggle_off_clears_ok_actions" {
  command = plan

  variables {
    notify_on_recovery = false
    alarms = {
      x = { metric_name = "ConsumedWriteCapacityUnits", threshold = 1 }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.this["x"].ok_actions) == 0
    error_message = "notify_on_recovery = false should leave ok_actions empty"
  }
}

run "existing_topic_is_used_verbatim" {
  command = plan

  variables {
    create_sns_topic       = false
    existing_sns_topic_arn = "arn:aws:sns:us-east-1:123456789012:shared"
    alarms = {
      x = { metric_name = "ConsumedWriteCapacityUnits", threshold = 1 }
    }
  }

  assert {
    condition = (
      length(aws_cloudwatch_metric_alarm.this["x"].alarm_actions) == 1 &&
      contains(aws_cloudwatch_metric_alarm.this["x"].alarm_actions, "arn:aws:sns:us-east-1:123456789012:shared")
    )
    error_message = "alarms should notify the existing topic when create_sns_topic = false"
  }
}

run "sns_topic_must_be_configured" {
  command = plan

  variables {
    create_sns_topic = false
    # existing_sns_topic_arn deliberately unset
    alarms = {}
  }

  expect_failures = [check.sns_topic_configured]
}
