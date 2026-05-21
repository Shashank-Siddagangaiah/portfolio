# Generate ATS-friendly 2-page PDF for Shashank_OCC_PlatformEng_Resume
# Run: C:/Users/shash/anaconda3/python.exe generate_occ_resume_pdf.py

from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, HRFlowable
from reportlab.lib import colors

OUT = r"C:\Users\shash\Music\VS_code\Claude_git\Resume\Shashank_OCC_PlatformEng_Resume.pdf"

NAVY  = colors.HexColor("#1B3A6B")
LGRAY = colors.HexColor("#555555")

def make_styles():
    name = ParagraphStyle(
        "Name", fontName="Helvetica-Bold", fontSize=16, leading=20,
        alignment=TA_CENTER, spaceAfter=2, textColor=NAVY,
    )
    contact = ParagraphStyle(
        "Contact", fontName="Helvetica", fontSize=10, leading=13,
        alignment=TA_CENTER, spaceAfter=4,
    )
    section_hdr = ParagraphStyle(
        "SectionHdr", fontName="Helvetica-Bold", fontSize=11, leading=14,
        spaceBefore=5, spaceAfter=2, textColor=NAVY,
    )
    job_title = ParagraphStyle(
        "JobTitle", fontName="Helvetica-Bold", fontSize=10.5, leading=14,
        spaceBefore=5, spaceAfter=1,
    )
    company = ParagraphStyle(
        "Company", fontName="Helvetica", fontSize=10, leading=13,
        spaceAfter=2.5, textColor=LGRAY,
    )
    body = ParagraphStyle(
        "Body", fontName="Helvetica", fontSize=10, leading=13, spaceAfter=2,
    )
    bullet = ParagraphStyle(
        "Bullet", fontName="Helvetica", fontSize=10, leading=13,
        leftIndent=12, firstLineIndent=-10, spaceAfter=2.0,
    )
    return dict(name=name, contact=contact, section_hdr=section_hdr,
                job_title=job_title, company=company, body=body, bullet=bullet)

def hr():
    return HRFlowable(width="100%", thickness=0.6, color=NAVY,
                      spaceAfter=2, spaceBefore=1)

def sp(h=3):
    return Spacer(1, h)

def section(s, label):
    return [Paragraph(label.upper(), s["section_hdr"]), hr()]

def b(s, text):
    return Paragraph(f"&#x2022;&#160;{text}", s["bullet"])

def skill_row(s, label, value):
    return Paragraph(f"<b>{label}:</b> {value}", s["body"])

def build_story(s):
    story = []

    # ── Header ───────────────────────────────────────────────────────────────
    story.append(Paragraph("SHASHANK SIDDAGANGAIAH", s["name"]))
    story.append(Paragraph(
        "Shashanksidhanth@gmail.com  |  773-517-4837  |  LinkedIn",
        s["contact"]
    ))
    story.append(hr())

    # ── Summary ───────────────────────────────────────────────────────────────
    story += section(s, "Professional Summary")
    story.append(Paragraph(
        "Platform Engineering Manager with 9+ years of experience building Internal Developer "
        "Portals (IDPs), self-service developer platforms, and cloud-native infrastructure tooling "
        "across insurance, healthcare, and e-commerce. Proven Product Owner of developer experience "
        "platforms -- managing roadmaps, sprint backlogs, and engaging engineering teams as internal "
        "customers. Hands-on with Backstage IDP, GitOps workflows, ArgoCD, GitHub Actions, "
        "Kubernetes, Helm, and AWS infrastructure. Consistent track record cutting deployment lead "
        "times by 30-40%, reducing developer onboarding time, improving DORA metrics, and driving "
        "golden-path template adoption across engineering organizations.",
        s["body"]
    ))

    # ── Skills ────────────────────────────────────────────────────────────────
    story += section(s, "Technical Skills")
    skills = [
        ("Developer Experience and IDP",
         "Backstage (service catalog, Software Templates/Scaffolder, plugin development, TechDocs), "
         "Internal Developer Portal (IDP), golden-path templates, self-service developer workflows, "
         "service onboarding automation, developer advocacy, platform as a product"),
        ("GitOps and CI/CD",
         "GitHub Actions, Jenkins, ArgoCD, Flux, GitOps, Git-based infrastructure delivery, "
         "CI/CD pipeline design, trunk-based development, reusable workflow components, "
         "composite actions, OIDC-based authentication"),
        ("Containers and Orchestration",
         "Kubernetes (K8s), Helm, Docker, Amazon EKS, RBAC, Pod Security, container security, "
         "microservice orchestration, Horizontal Pod Autoscaler, Kubernetes Operators"),
        ("Cloud and Infrastructure",
         "AWS (EC2, VPC, Security Groups, IAM, KMS, S3, Lambda, Kinesis, Glue, Redshift, EMR), "
         "Microsoft Azure (Synapse, Data Factory, Fabric), AWS CLI, Infrastructure as Code"),
        ("Observability and Monitoring",
         "Prometheus, Grafana, Datadog, Splunk, ELK Stack (Elasticsearch, Logstash, Kibana), "
         "PagerDuty, SLA/SLO monitoring, DORA metrics, alerting pipelines"),
        ("Languages",
         "Python, TypeScript, Node.js, SQL (PostgreSQL, T-SQL), Java, Scala"),
        ("Leadership and Product Ownership",
         "Agile, Scrum, Product Owner, Technical Roadmapping, Backlog Management, Sprint Planning, "
         "Developer Advocacy, Stakeholder Engagement, Hiring, Performance Management, OKRs, "
         "Team Topologies"),
        ("Data and Integration",
         "Snowflake, Databricks, Apache Kafka, Apache Spark, Power BI, Tableau, "
         "Azure Data Factory, AWS Glue"),
    ]
    for label, value in skills:
        story.append(skill_row(s, label, value))
        story.append(sp(1))

    # ── Experience ────────────────────────────────────────────────────────────
    story += section(s, "Professional Experience")

    # PEMCO
    story.append(Paragraph("Platform Engineering Lead", s["job_title"]))
    story.append(Paragraph(
        "PEMCO Insurance / Bourntec Solutions  --  Chicago, IL  |  July 2025 - Present",
        s["company"]))
    for t in [
        "Owned 1-to-3-year platform engineering roadmap as Product Owner; managed backlog "
        "prioritization, led sprint planning and reviews, and aligned tooling investments by "
        "treating engineering teams as internal customers to drive developer experience improvements.",
        "Configured and extended Backstage IDP service catalog to centralize ownership metadata "
        "for 50+ microservices and data services; reduced developer onboarding time by 30% through "
        "standardized catalog-info YAML and component tagging.",
        "Built self-service Software Templates in Backstage Scaffolder to standardize project "
        "scaffolding, CI/CD pipeline wiring, and cloud resource provisioning -- codifying "
        "organizational best practices as golden-path templates used across all engineering teams.",
        "Engineered automated GitHub Actions CI/CD workflows cutting deployment latency by 30% "
        "via parallelized build, test, and release automation aligned with GitOps delivery practices.",
        "Designed API-first microservices enabling self-service access patterns for internal "
        "engineering teams; improved data accuracy by 25% through standardized interfaces and "
        "automated schema validation.",
        "Orchestrated end-to-end platform infrastructure across Microsoft Fabric and Databricks, "
        "ensuring 99.9% availability and SLA compliance for critical engineering workloads.",
    ]:
        story.append(b(s, t))

    # Kemper
    story.append(Paragraph("Platform Engineering Manager", s["job_title"]))
    story.append(Paragraph(
        "Kemper Insurance / Bourntec Solutions  --  Chicago, IL  |  August 2023 - July 2025",
        s["company"]))
    for t in [
        "Managed 8 direct reports (Platform and Data Engineers) in an Agile environment; owned "
        "hiring, quarterly performance reviews, OKRs, and technical mentorship as engineering "
        "manager for the Developer Experience pod.",
        "Acted as Product Owner for the internal developer platform -- ran sprint backlog grooming, "
        "led planning and retrospectives, and gathered requirements from 8 engineering teams as "
        "internal customers to prioritize tooling adoption and improve developer experience.",
        "Implemented GitHub Actions CI/CD pipelines and GitOps-based delivery workflows; reduced "
        "deployment lead time by 40% and established trunk-based delivery across engineering teams.",
        "Built reusable self-service platform libraries and golden-path pipeline components in "
        "Python, reducing development effort by 25% across 6 teams -- tracked via internal NPS "
        "and ticket-volume metrics.",
        "Integrated Prometheus and Grafana monitoring dashboards providing real-time visibility "
        "into pipeline health, DORA metrics, and SLA compliance across the developer platform.",
        "Enforced Kubernetes RBAC policies and least-privilege IAM roles to align platform security "
        "posture with enterprise compliance requirements (HIPAA, GDPR).",
        "Led enterprise-wide modernization of 70+ legacy reporting tools to self-service Power BI "
        "pipelines, cutting licensing costs by 40% and improving stakeholder adoption.",
    ]:
        story.append(b(s, t))

    # Select Rehab
    story.append(Paragraph("Platform / Infrastructure Engineer", s["job_title"]))
    story.append(Paragraph(
        "Select Rehabilitation  --  Chicago, IL  |  May 2022 - August 2023",
        s["company"]))
    for t in [
        "Deployed and managed containerized microservice infrastructure using Docker and Kubernetes "
        "on AWS EKS; improved deployment automation, scalability, and operational reliability for "
        "healthcare data workloads.",
        "Built GitHub Actions pipelines for automated testing, container image builds, and "
        "environment deployments; established CI/CD best practices and GitOps delivery patterns "
        "across the engineering organization.",
        "Provisioned and secured cloud environments using AWS EC2, VPC, Security Groups, and IAM; "
        "enforced network isolation and least-privilege access for HIPAA-regulated workloads.",
        "Designed scalable ETL/ELT pipelines using Azure Data Factory, Databricks, and AWS Glue; "
        "migrated 100+ IBM Cognos BI reports to an in-house Python-based platform, cutting "
        "reporting costs by 20%.",
    ]:
        story.append(b(s, t))

    # Amazon
    story.append(Paragraph("Senior Data Analyst", s["job_title"]))
    story.append(Paragraph(
        "Amazon (Pricing Analytics, Amazon Fresh, Amazon Pay)  --  Bangalore, India  |  May 2016 - December 2020",
        s["company"]))
    for t in [
        "Partnered with Product Managers, Software Engineers, and Data Scientists to design "
        "platform data architectures supporting global expansion of Amazon Fresh "
        "(US, UK, Japan, Germany).",
        "Developed automated Python-based backend services and analytics pipelines for internal "
        "engineering teams, improving data refresh efficiency by 30% and enabling near-real-time "
        "business insights.",
        "Led large-scale refund-tracking initiative during COVID-19, consolidating fragmented data "
        "via APIs to reduce customer service contacts by 90%+ (3,000 to 200 per week).",
        "Delivered executive-facing Tableau dashboards for Weekly Business Reporting (WBR) "
        "consumed by leadership across 22+ business categories.",
    ]:
        story.append(b(s, t))

    # ── Certifications ────────────────────────────────────────────────────────
    story += section(s, "Certifications")
    for c in [
        "AWS Certified Data Engineer -- Associate",
        "Tableau Desktop Specialist",
        "(Pursuing) AWS Certified DevOps Engineer -- Professional",
    ]:
        story.append(b(s, c))

    # ── Education ─────────────────────────────────────────────────────────────
    story += section(s, "Education")
    story.append(Paragraph("MS in Business Analytics  |  GPA: 3.9", s["job_title"]))
    story.append(Paragraph(
        "University of Illinois Chicago, Chicago, IL  |  January 2021 - May 2022",
        s["company"]))

    return story


def main():
    doc = SimpleDocTemplate(
        OUT,
        pagesize=letter,
        leftMargin=0.6 * inch,
        rightMargin=0.6 * inch,
        topMargin=0.55 * inch,
        bottomMargin=0.55 * inch,
        title="Shashank Siddagangaiah - Platform Engineering Manager",
        author="Shashank Siddagangaiah",
    )
    s = make_styles()
    story = build_story(s)
    doc.build(story)
    print(f"PDF saved: {OUT}")


if __name__ == "__main__":
    main()
