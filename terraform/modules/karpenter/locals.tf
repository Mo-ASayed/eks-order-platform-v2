locals {
  interruption_event_patterns = {
    spot_interruption = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Spot Instance Interruption Warning"]
    }
    rebalance_recommendation = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance Rebalance Recommendation"]
    }
    instance_state_change = {
      source      = ["aws.ec2"]
      detail-type = ["EC2 Instance State-change Notification"]
    }
    scheduled_change = {
      source      = ["aws.health"]
      detail-type = ["AWS Health Event"]
      detail = {
        service           = ["EC2"]
        eventTypeCategory = ["scheduledChange"]
      }
    }
  }
}
