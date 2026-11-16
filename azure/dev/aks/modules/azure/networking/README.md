# networking (Azure)

VNet of one workspace with one system and one user subnet, a default-rules NSG per
subnet and a NAT gateway with a static public IP as explicit egress. CIDRs come only
from the approved networking object (network catalog, Regla A); nothing is invented
here. The workspace resource group must already exist; this module never creates it.
