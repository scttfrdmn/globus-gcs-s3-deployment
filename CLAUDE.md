# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- CloudFormation validation: `aws cloudformation validate-template --template-body file://globus-gcs-s3-template.yaml`
- CloudFormation linting: `cfn-lint globus-gcs-s3-template.yaml`
- YAML linting: `yamllint globus-gcs-s3-template.yaml`
- Markdown linting: `markdownlint README.md docs/*.md`

## Code Style Guidelines

- **YAML**: Use 2-space indentation, explicit mapping of types
- **CloudFormation**: Follow AWS best practices for resource naming
- **Markdown**: Use ATX-style headers (# Header), proper heading hierarchy
- **Naming Conventions**: Use PascalCase for CloudFormation resources and outputs, camelCase for parameters
- **Error Handling**: Implement robust error handling in user-data scripts with error trapping
- **Documentation**: Maintain comprehensive documentation in the docs/ directory
- **Resource Tags**: Consistently tag all resources with "Name" at minimum